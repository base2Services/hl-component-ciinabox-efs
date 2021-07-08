require 'yaml'

describe 'compiled component ciinabox-efs' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/security_group_rules.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/security_group_rules/ciinabox-efs.compiled.yaml") }
  
  context "Resource" do

    
    context "CiinaboxEfsCustomResourceRole" do
      let(:resource) { template["Resources"]["CiinaboxEfsCustomResourceRole"] }

      it "is of type AWS::IAM::Role" do
          expect(resource["Type"]).to eq("AWS::IAM::Role")
      end
      
      it "to have property AssumeRolePolicyDocument" do
          expect(resource["Properties"]["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>["lambda.amazonaws.com"]}, "Action"=>"sts:AssumeRole"}]})
      end
      
      it "to have property Path" do
          expect(resource["Properties"]["Path"]).to eq("/")
      end
      
      it "to have property Policies" do
          expect(resource["Properties"]["Policies"]).to eq([{"PolicyName"=>"ciinabox-efs", "PolicyDocument"=>{"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Action"=>["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], "Resource"=>"*"}, {"Effect"=>"Allow", "Action"=>["elasticfilesystem:UpdateFileSystem", "elasticfilesystem:CreateFileSystem", "elasticfilesystem:DescribeFileSystems", "elasticfilesystem:ListTagsForResource", "elasticfilesystem:TagResource", "elasticfilesystem:UntagResource"], "Resource"=>"*"}]}}])
      end
      
    end
    
    context "CiinaboxEfsCustomResourceFunction" do
      let(:resource) { template["Resources"]["CiinaboxEfsCustomResourceFunction"] }

      it "is of type AWS::Lambda::Function" do
          expect(resource["Type"]).to eq("AWS::Lambda::Function")
      end
      
      it "to have property Code" do
          expect(resource["Properties"]["Code"]).to eq({"ZipFile"=>"import cfnresponse\nimport boto3\nimport hashlib\nimport time\n\nimport logging\nlogger = logging.getLogger(__name__)\nlogger.setLevel(logging.INFO)\n\ndef get_creation_token(name):\n  return hashlib.md5(name.encode('utf-8')).hexdigest()\n\ndef create_filesystem(name):\n  client = boto3.client('efs')\n  resp = client.create_file_system(\n    CreationToken=get_creation_token(name),\n    PerformanceMode='generalPurpose',\n    Encrypted=False,\n    ThroughputMode='bursting',\n    Backup=True\n  )\n  return resp['FileSystemId']\n\ndef get_filesystem_id(name):\n  client = boto3.client('efs')\n  resp = client.describe_file_systems(\n    CreationToken=get_creation_token(name)\n  )\n  if resp['FileSystems']:\n    return resp['FileSystems'][0]['FileSystemId']\n  return None\n\ndef get_filesystem_state(filesystem):\n  client = boto3.client('efs')\n  resp = client.describe_file_systems(\n    FileSystemId=filesystem\n  )\n  return resp['FileSystems'][0]['LifeCycleState']\n\ndef wait_until(success, filesystem, timeout=120, period=3):\n  end = time.time() + timeout\n  while time.time() < end:\n    state = get_filesystem_state(filesystem)\n    logger.info(f'filesystem is {state}, waiting to reach the {success} state')\n    if state == success: \n      return True\n    elif state == 'error':\n      raise WaitError(\"filesystem is in an error state\")\n    time.sleep(period)\n  return False\n\ndef tag_filesystem(filesystem, tags):\n  client = boto3.client('efs')\n  client.tag_resource(\n    ResourceId=filesystem,\n    Tags=tags\n  )\n\nclass WaitError(Exception):\n  pass\n\n\ndef lambda_handler(event, context):\n\n  try:\n\n    logger.info(event)\n    # Globals\n    responseData = {}\n    physicalResourceId = None\n    name = event['ResourceProperties']['Name']\n    tags = event['ResourceProperties']['Tags']\n\n    if event['RequestType'] == 'Create':\n      filesystem = get_filesystem_id(name)\n      if filesystem is None:\n        logger.info(f'creating new filesystem')\n        filesystem = create_filesystem(name)\n        print(f'filesystem {filesystem} created')\n        wait_until('available', filesystem)\n      else:\n        print(f'filesystem {filesystem} already exists')\n      \n      tag_filesystem(filesystem, tags)\n      physicalResourceId = filesystem\n\n    elif event['RequestType'] == 'Update':\n      tag_filesystem(filesystem, tags)\n      physicalResourceId = event['PhysicalResourceId']\n      \n    elif event['RequestType'] == 'Delete':\n      physicalResourceId = event['PhysicalResourceId']\n    \n    cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, physicalResourceId)\n\n  except Exception as e:\n    logger.error('failed to cleanup bucket', exc_info=True)\n    cfnresponse.send(event, context, cfnresponse.FAILED, {})\n\n"})
      end
      
      it "to have property Handler" do
          expect(resource["Properties"]["Handler"]).to eq("index.lambda_handler")
      end
      
      it "to have property Runtime" do
          expect(resource["Properties"]["Runtime"]).to eq("python3.7")
      end
      
      it "to have property Role" do
          expect(resource["Properties"]["Role"]).to eq({"Fn::GetAtt"=>["CiinaboxEfsCustomResourceRole", "Arn"]})
      end
      
      it "to have property Timeout" do
          expect(resource["Properties"]["Timeout"]).to eq(60)
      end
      
    end
    
    context "FileSystem" do
      let(:resource) { template["Resources"]["FileSystem"] }

      it "is of type Custom::FileSystem" do
          expect(resource["Type"]).to eq("Custom::FileSystem")
      end
      
      it "to have property ServiceToken" do
          expect(resource["Properties"]["ServiceToken"]).to eq({"Fn::GetAtt"=>["CiinaboxEfsCustomResourceFunction", "Arn"]})
      end
      
      it "to have property Name" do
          expect(resource["Properties"]["Name"]).to eq({"Fn::Sub"=>"/${EnvironmentName}-ciinabox"})
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([[], [], {"Key"=>"Environment", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}, {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ciinabox-FileSystem"}}])
      end
      
    end
    
    context "SecurityGroupEFS" do
      let(:resource) { template["Resources"]["SecurityGroupEFS"] }

      it "is of type AWS::EC2::SecurityGroup" do
          expect(resource["Type"]).to eq("AWS::EC2::SecurityGroup")
      end
      
      it "to have property GroupDescription" do
          expect(resource["Properties"]["GroupDescription"]).to eq({"Fn::Sub"=>"${EnvironmentName} ciinabox-efs"})
      end
      
      it "to have property VpcId" do
          expect(resource["Properties"]["VpcId"]).to eq({"Ref"=>"VPCId"})
      end
      
      it "to have property SecurityGroupIngress" do
          expect(resource["Properties"]["SecurityGroupIngress"]).to eq([{"FromPort"=>2049, "IpProtocol"=>"TCP", "ToPort"=>2049, "Description"=>{"Fn::Sub"=>"Use IP blocks and SG group"}, "CidrIp"=>{"Fn::Sub"=>"127.0.0.1/32"}}, {"FromPort"=>2049, "IpProtocol"=>"TCP", "ToPort"=>2049, "Description"=>{"Fn::Sub"=>"Use IP blocks and SG group"}, "CidrIp"=>{"Fn::Sub"=>"127.0.0.2/32"}}, {"FromPort"=>2049, "IpProtocol"=>"TCP", "ToPort"=>2049, "Description"=>{"Fn::Sub"=>"Use IP blocks and SG group"}, "SourceSecurityGroupId"=>{"Fn::Sub"=>"sg-rkqufht"}}])
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([[], [], {"Key"=>"Environment", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}, {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"${EnvironmentName}-ciinabox-FileSystem"}}])
      end
      
    end
    
    context "MountTarget0" do
      let(:resource) { template["Resources"]["MountTarget0"] }

      it "is of type AWS::EFS::MountTarget" do
          expect(resource["Type"]).to eq("AWS::EFS::MountTarget")
      end
      
      it "to have property FileSystemId" do
          expect(resource["Properties"]["FileSystemId"]).to eq({"Ref"=>"FileSystem"})
      end
      
      it "to have property SecurityGroups" do
          expect(resource["Properties"]["SecurityGroups"]).to eq([{"Ref"=>"SecurityGroupEFS"}])
      end
      
      it "to have property SubnetId" do
          expect(resource["Properties"]["SubnetId"]).to eq({"Fn::Select"=>[0, {"Ref"=>"SubnetIds"}]})
      end
      
    end
    
    context "MountTarget1" do
      let(:resource) { template["Resources"]["MountTarget1"] }

      it "is of type AWS::EFS::MountTarget" do
          expect(resource["Type"]).to eq("AWS::EFS::MountTarget")
      end
      
      it "to have property FileSystemId" do
          expect(resource["Properties"]["FileSystemId"]).to eq({"Ref"=>"FileSystem"})
      end
      
      it "to have property SecurityGroups" do
          expect(resource["Properties"]["SecurityGroups"]).to eq([{"Ref"=>"SecurityGroupEFS"}])
      end
      
      it "to have property SubnetId" do
          expect(resource["Properties"]["SubnetId"]).to eq({"Fn::Select"=>[1, {"Ref"=>"SubnetIds"}]})
      end
      
    end
    
    context "MountTarget2" do
      let(:resource) { template["Resources"]["MountTarget2"] }

      it "is of type AWS::EFS::MountTarget" do
          expect(resource["Type"]).to eq("AWS::EFS::MountTarget")
      end
      
      it "to have property FileSystemId" do
          expect(resource["Properties"]["FileSystemId"]).to eq({"Ref"=>"FileSystem"})
      end
      
      it "to have property SecurityGroups" do
          expect(resource["Properties"]["SecurityGroups"]).to eq([{"Ref"=>"SecurityGroupEFS"}])
      end
      
      it "to have property SubnetId" do
          expect(resource["Properties"]["SubnetId"]).to eq({"Fn::Select"=>[2, {"Ref"=>"SubnetIds"}]})
      end
      
    end
    
    context "MountTarget3" do
      let(:resource) { template["Resources"]["MountTarget3"] }

      it "is of type AWS::EFS::MountTarget" do
          expect(resource["Type"]).to eq("AWS::EFS::MountTarget")
      end
      
      it "to have property FileSystemId" do
          expect(resource["Properties"]["FileSystemId"]).to eq({"Ref"=>"FileSystem"})
      end
      
      it "to have property SecurityGroups" do
          expect(resource["Properties"]["SecurityGroups"]).to eq([{"Ref"=>"SecurityGroupEFS"}])
      end
      
      it "to have property SubnetId" do
          expect(resource["Properties"]["SubnetId"]).to eq({"Fn::Select"=>[3, {"Ref"=>"SubnetIds"}]})
      end
      
    end
    
    context "MountTarget4" do
      let(:resource) { template["Resources"]["MountTarget4"] }

      it "is of type AWS::EFS::MountTarget" do
          expect(resource["Type"]).to eq("AWS::EFS::MountTarget")
      end
      
      it "to have property FileSystemId" do
          expect(resource["Properties"]["FileSystemId"]).to eq({"Ref"=>"FileSystem"})
      end
      
      it "to have property SecurityGroups" do
          expect(resource["Properties"]["SecurityGroups"]).to eq([{"Ref"=>"SecurityGroupEFS"}])
      end
      
      it "to have property SubnetId" do
          expect(resource["Properties"]["SubnetId"]).to eq({"Fn::Select"=>[4, {"Ref"=>"SubnetIds"}]})
      end
      
    end
    
  end

end