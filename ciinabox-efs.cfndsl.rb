CloudFormation do
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

  Logs_LogGroup(:CiinaboxEfsCustomResourceLogGroup) {
    LogGroupName FnSub("/aws/lambda/${CiinaboxEfsCustomResourceFunction}")
    RetentionInDays 30
  }

  Lambda_Function(:CiinaboxEfsCustomResourceFunction) {
    Code({
      ZipFile: <<~CODE
        import cfnresponse
        import boto3
        import uuid
        import time

        import logging
        logger = logging.getLogger(__name__)
        logger.setLevel(logging.INFO)

        def create_fs():
          client = boto3.client('efs')
          resp = client.create_file_system(
              CreationToken=uuid.uuid4().hex,
              PerformanceMode='generalPurpose',
              Encrypted=False,
              ThroughputMode='bursting',
              Backup=True
          )
          return resp['FileSystemId']
      
        def get_fs_state(fsid):
            client = boto3.client('efs')
            resp = client.describe_file_systems(
                FileSystemId=fsid
            )
            return resp['FileSystems'][0]['LifeCycleState']
        
        def wait_until(success, id, timeout=120, period=3):
            end = time.time() + timeout
            while time.time() < end:
                state = get_fs_state(id)
                print(f'filesystem is {state}, waiting to reach the {success} state')
                if state == success: 
                    return True
                elif state == 'error':
                    raise WaitError("filesystem is in an error state")
                time.sleep(period)
            return False
        
        class WaitError(Exception):
            pass


        def lambda_handler(event, context):

          try:

            logger.info(event)
            # Globals
            responseData = {}
            physicalResourceId = None
            # tags = event['ResourceProperties']['Tags']

            if event['RequestType'] == 'Create':
              physicalResourceId = create_fs()
              logger.info(f'filesystem {physicalResourceId} created')
              wait_until('available', id)

            elif event['RequestType'] == 'Update':
              physicalResourceId = event['PhysicalResourceId']
              
            elif event['RequestType'] == 'Delete':
              physicalResourceId = event['PhysicalResourceId']
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, physicalResourceId)

          except Exception as e:
            logger.error('failed to cleanup bucket', exc_info=True)
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

      CODE
    })
    Handler "index.lambda_handler"
    Runtime "python3.7"
    Role FnGetAtt(:CiinaboxEfsCustomResourceRole, :Arn)
    Timeout 60
  }

  Resource(:CiinaboxEfsCustomResource) {
    Type "Custom::CleanUpBucket"
    Property 'ServiceToken', FnGetAtt(:CiinaboxEfsCustomResourceFunction, :Arn)
  }
end