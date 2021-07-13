CloudFormation do

  tags = []
  tags.push(
    { Key: 'Environment', Value: Ref(:EnvironmentName) },
    { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }
  )

  IAM_Role(:CiinaboxEfsCustomResourceRole) {
    AssumeRolePolicyDocument({
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Principal: {
            Service: [
              'lambda.amazonaws.com'
            ]
          },
          Action: 'sts:AssumeRole'
        }
      ]
    })
    Path '/'
    Policies([
      {
        PolicyName: 'ciinabox-efs',
        PolicyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              Resource: '*'
            },
            {
              Effect: 'Allow',
              Action: [
                'elasticfilesystem:UpdateFileSystem',
                'elasticfilesystem:CreateFileSystem',
                'elasticfilesystem:DescribeFileSystems',
                'elasticfilesystem:ListTagsForResource',
                'elasticfilesystem:TagResource',
                'elasticfilesystem:UntagResource'
              ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  Lambda_Function(:CiinaboxEfsCustomResourceFunction) {
    Code({
      ZipFile: <<~CODE
        import cfnresponse
        import boto3
        import hashlib
        import time

        import logging
        logger = logging.getLogger(__name__)
        logger.setLevel(logging.INFO)

        def get_creation_token(name):
          return hashlib.md5(name.encode('utf-8')).hexdigest()
      
        def create_filesystem(name):
          client = boto3.client('efs')
          resp = client.create_file_system(
            CreationToken=get_creation_token(name),
            PerformanceMode='generalPurpose',
            Encrypted=False,
            ThroughputMode='bursting',
            Backup=True
          )
          return resp['FileSystemId']
        
        def get_filesystem_id(name):
          client = boto3.client('efs')
          resp = client.describe_file_systems(
            CreationToken=get_creation_token(name)
          )
          if resp['FileSystems']:
            return resp['FileSystems'][0]['FileSystemId']
          return None
        
        def get_filesystem_state(filesystem):
          client = boto3.client('efs')
          resp = client.describe_file_systems(
            FileSystemId=filesystem
          )
          return resp['FileSystems'][0]['LifeCycleState']
        
        def wait_until(success, filesystem, timeout=120, period=3):
          end = time.time() + timeout
          while time.time() < end:
            state = get_filesystem_state(filesystem)
            logger.info(f'filesystem is {state}, waiting to reach the {success} state')
            if state == success: 
              return True
            elif state == 'error':
              raise WaitError("filesystem is in an error state")
            time.sleep(period)
          return False

        def tag_filesystem(filesystem, tags):
          client = boto3.client('efs')
          client.tag_resource(
            ResourceId=filesystem,
            Tags=tags
          )
        
        class WaitError(Exception):
          pass


        def lambda_handler(event, context):

          try:

            logger.info(event)
            # Globals
            responseData = {}
            physicalResourceId = None
            name = event['ResourceProperties'].get('Name')
            tags = event['ResourceProperties'].get('Tags')
            tags.append({'Key': 'Name', 'Value': name})

            if event['RequestType'] == 'Create':
              filesystem = get_filesystem_id(name)
              if filesystem is None:
                logger.info(f'creating new filesystem')
                filesystem = create_filesystem(name)
                print(f'filesystem {filesystem} created')
                wait_until('available', filesystem)
              else:
                print(f'filesystem {filesystem} already exists')
              
              tag_filesystem(filesystem, tags)
              physicalResourceId = filesystem

            elif event['RequestType'] == 'Update':
              tag_filesystem(filesystem, tags)
              physicalResourceId = event['PhysicalResourceId']
              
            elif event['RequestType'] == 'Delete':
              physicalResourceId = event['PhysicalResourceId']
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, physicalResourceId)

          except Exception as e:
            logger.error('ciinabox efs custom resource caught an unexpected exception', exc_info=True)
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

      CODE
    })
    Handler "index.lambda_handler"
    Runtime "python3.7"
    Role FnGetAtt(:CiinaboxEfsCustomResourceRole, :Arn)
    Timeout 60
  }

  Condition(:VolumeNameSet, FnNot(FnEquals(Ref(:VolumeName), '')))

  Resource(:FileSystem) {
    Type "Custom::FileSystem"
    Property 'ServiceToken', FnGetAtt(:CiinaboxEfsCustomResourceFunction, :Arn)
    Property 'Name', FnIf(:VolumeNameSet, Ref(:VolumeName), FnSub("/${EnvironmentName}-ciinabox"))
    Property 'Tags', tags
  }

  Output(:FileSystem) {
    Value(Ref('FileSystem'))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-FileSystem")
  }

  security_group_rules = external_parameters.fetch(:security_group_rules, [])
  
  EC2_SecurityGroup('SecurityGroupEFS') do
    GroupDescription FnSub("${EnvironmentName} #{external_parameters[:component_name]}")
    VpcId Ref('VPCId')
    if security_group_rules.any?
      SecurityGroupIngress generate_security_group_rules(security_group_rules,ip_blocks)
    end
    Tags [{Key: 'Name', Value:  FnSub("${EnvironmentName}-ciinabox-filesystem")}] + tags
  end

  external_parameters[:max_availability_zones].times do |az|

    matches = ((az+1)..external_parameters[:max_availability_zones]).to_a
    Condition("CreateEFSMount#{az}",
      matches.length == 1 ? FnEquals(Ref(:AvailabilityZones), external_parameters[:max_availability_zones]) : FnOr(matches.map { |i| FnEquals(Ref(:AvailabilityZones), i) })
    )

    EFS_MountTarget("MountTarget#{az}") do
      Condition("CreateEFSMount#{az}")
      FileSystemId Ref('FileSystem')
      SecurityGroups [ Ref("SecurityGroupEFS") ]
      SubnetId FnSelect(az, Ref('SubnetIds'))
    end

  end

  unless access_points.empty?
    access_points.each do |ap|
      EFS_AccessPoint("#{ap['name']}AccessPoint") do
        AccessPointTags [{Key: 'Name', Value:  FnSub("${EnvironmentName}-ciinabox-ap-#{ap['name']}")}] + tags
        FileSystemId Ref('FileSystem')
        PosixUser ap['posix_user'] if ap.has_key?('posix_user')
        RootDirectory ap['root_directory'] if ap.has_key?('root_directory')
      end

      Output("#{ap['name']}AccessPoint") {
        Value(Ref("#{ap['name']}AccessPoint"))
        Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{ap['name']}AccessPoint")
      }
    end
  end

  
end