require 'yaml'

describe 'compiled component ciinabox-efs' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/default.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/default/ciinabox-efs.compiled.yaml") }
  
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
    
    context "CiinaboxEfsCustomResourceLogGroup" do
      let(:resource) { template["Resources"]["CiinaboxEfsCustomResourceLogGroup"] }

      it "is of type AWS::Logs::LogGroup" do
          expect(resource["Type"]).to eq("AWS::Logs::LogGroup")
      end
      
      it "to have property LogGroupName" do
          expect(resource["Properties"]["LogGroupName"]).to eq({"Fn::Sub"=>"/aws/lambda/${CiinaboxEfsCustomResourceFunction}"})
      end
      
      it "to have property RetentionInDays" do
          expect(resource["Properties"]["RetentionInDays"]).to eq(30)
      end
      
    end
    
    context "CiinaboxEfsCustomResourceFunction" do
      let(:resource) { template["Resources"]["CiinaboxEfsCustomResourceFunction"] }

      it "is of type AWS::Lambda::Function" do
          expect(resource["Type"]).to eq("AWS::Lambda::Function")
      end
      
      it "to have property Code" do
          expect(resource["Properties"]["Code"]).to eq({"ZipFile"=>"import cfnresponse\nimport boto3\nimport uuid\nimport time\n\nimport logging\nlogger = logging.getLogger(__name__)\nlogger.setLevel(logging.INFO)\n\ndef create_fs():\n  client = boto3.client('efs')\n  resp = client.create_file_system(\n      CreationToken=uuid.uuid4().hex,\n      PerformanceMode='generalPurpose',\n      Encrypted=False,\n      ThroughputMode='bursting',\n      Backup=True\n  )\n  return resp['FileSystemId']\n\ndef get_fs_state(fsid):\n    client = boto3.client('efs')\n    resp = client.describe_file_systems(\n        FileSystemId=fsid\n    )\n    return resp['FileSystems'][0]['LifeCycleState']\n\ndef wait_until(success, id, timeout=120, period=3):\n    end = time.time() + timeout\n    while time.time() < end:\n        state = get_fs_state(id)\n        print(f'filesystem is {state}, waiting to reach the {success} state')\n        if state == success: \n            return True\n        elif state == 'error':\n            raise WaitError(\"filesystem is in an error state\")\n        time.sleep(period)\n    return False\n\nclass WaitError(Exception):\n    pass\n\n\ndef lambda_handler(event, context):\n\n  try:\n\n    logger.info(event)\n    # Globals\n    responseData = {}\n    physicalResourceId = None\n    # tags = event['ResourceProperties']['Tags']\n\n    if event['RequestType'] == 'Create':\n      physicalResourceId = create_fs()\n      logger.info(f'filesystem {physicalResourceId} created')\n      wait_until('available', id)\n\n    elif event['RequestType'] == 'Update':\n      physicalResourceId = event['PhysicalResourceId']\n      \n    elif event['RequestType'] == 'Delete':\n      physicalResourceId = event['PhysicalResourceId']\n    \n    cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, physicalResourceId)\n\n  except Exception as e:\n    logger.error('failed to cleanup bucket', exc_info=True)\n    cfnresponse.send(event, context, cfnresponse.FAILED, {})\n\n"})
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
    
    context "CiinaboxEfsCustomResource" do
      let(:resource) { template["Resources"]["CiinaboxEfsCustomResource"] }

      it "is of type Custom::CleanUpBucket" do
          expect(resource["Type"]).to eq("Custom::CleanUpBucket")
      end
      
      it "to have property ServiceToken" do
          expect(resource["Properties"]["ServiceToken"]).to eq({"Fn::GetAtt"=>["CiinaboxEfsCustomResourceFunction", "Arn"]})
      end
      
    end
    
  end

end