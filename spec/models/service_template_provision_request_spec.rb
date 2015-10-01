require "spec_helper"

describe ServiceTemplateProvisionRequest do
  let(:admin) { FactoryGirl.create(:user_admin) }
  context "with multiple tasks" do
    before(:each) do
      @request   = FactoryGirl.create(:service_template_provision_request, :description => 'Service Request', :userid => admin.userid)

      @task_1    = FactoryGirl.create(:service_template_provision_task,    :description => 'Task 1'         , :userid => admin.userid, :status => "Ok",:state => "pending", :miq_request_id => @request.id, :request_type => "clone_to_service")
      @task_1_1  = FactoryGirl.create(:service_template_provision_task,    :description => 'Task 1 - 1'     , :userid => admin.userid, :status => "Ok",:state => "pending", :miq_request_id => @request.id, :request_type => "clone_to_service")
      @task_2    = FactoryGirl.create(:service_template_provision_task,    :description => 'Task 2'         , :userid => admin.userid, :status => "Ok",:state => "pending", :miq_request_id => @request.id, :request_type => "clone_to_service")
      @task_2_1  = FactoryGirl.create(:service_template_provision_task,    :description => 'Task 2 - 1'     , :userid => admin.userid, :status => "Ok",:state => "pending", :miq_request_id => @request.id, :request_type => "clone_to_service")

      @task_1.miq_request_tasks << @task_1_1
      @task_2.miq_request_tasks << @task_2_1
    end

    it "update_request_status - no message" do
      expect(@request.message).to eq("Service_Template_Provisioning - Request Created")
      @request.update_request_status
      expect(@request.message).to eq("Pending = 4")
    end

    it "update_request_status with message override" do
      expect(@request.message).to eq("Service_Template_Provisioning - Request Created")
      @request.update_attribute(:options, :user_message => "New test message")
      @request.update_request_status
      expect(@request.message).to eq("New test message")
    end

    it "pending state" do
      @request.update_request_status
      @request.message.should == "Pending = 4"
      @request.state.should   == "pending"
      @request.status.should  == "Ok"
    end

    it "queued state" do
      @task_1_1.update_and_notify_parent({:state => "queued", :status => "Ok", :message => "Test Message"})
      @request.reload
      @request.message.should == "Pending = 2; Queued = 2"
      @request.state.should   == "active"
      @request.status.should  == "Ok"
    end

    it "all queued state" do
      @task_1_1.update_and_notify_parent({:state => "queued", :status => "Ok", :message => "Test Message"})
      @task_2_1.update_and_notify_parent({:state => "queued", :status => "Ok", :message => "Test Message"})
      @request.reload
      @request.message.should == "Queued = 4"
      @request.state.should   == "queued"
      @request.status.should  == "Ok"
    end

    it "active state" do
      @task_1_1.update_and_notify_parent({:state => "active", :status => "Ok", :message => "Test Message"})
      @request.reload
      @request.message.should == "Active = 2; Pending = 2"
      @request.state.should   == "active"
      @request.status.should  == "Ok"
    end

    it "partial tasks finished" do
      @task_1_1.update_and_notify_parent({:state => "finished", :status => "Ok", :message => "Test Message"})
      @request.reload
      @request.message.should == "Finished = 1; Pending = 2; Provisioned = 1"
      @request.state.should   == "active"
      @request.status.should  == "Ok"
    end

    it "finished state" do
      @task_1.update_attributes(:state => "finished")
      @task_1_1.update_and_notify_parent({:state => "finished", :status => "Ok", :message => "Test Message"})
      @task_2.update_attributes(:state => "finished")
      @task_2_1.update_and_notify_parent({:state => "finished", :status => "Ok", :message => "Test Message"})
      @request.reload
      @request.message.should == "Request complete"
      @request.state.should   == "finished"
      @request.status.should  == "Ok"
    end

    it "active with error state" do
      @task_1_1.update_and_notify_parent({:state => "active", :status => "Error", :message => "Error Message"})
      @request.reload
      @request.message.should == "Active = 2; Pending = 2"
      @request.state.should   == "active"
      @request.status.should  == "Error"
    end

    it "partial finish with error state" do
      @task_1_1.update_and_notify_parent({:state => "finished", :status => "Error", :message => "Error Message"})
      @request.reload
      @request.message.should == "Finished = 2; Pending = 2"
      @request.state.should   == "active"
      @request.status.should  == "Error"
    end

    it "finished with errors state" do
      @task_1_1.update_and_notify_parent({:state => "finished", :status => "Error", :message => "Error Message"})
      @task_2_1.update_and_notify_parent(:state => "finished", :status => "Error", :message => "Test Message")
      @request.reload
      @request.message.should == "Request completed with errors"
      @request.state.should   == "finished"
      @request.status.should  == "Error"
    end

    it "generic service do_request" do
      lambda { @task_1_1.do_request }.should_not raise_error
      @task_1_1.state.should == 'provisioned'
    end
  end

  describe "#make_request" do
    let(:service_template) { FactoryGirl.create(:service_template, :name => "My Service Template") }
    let(:alt_user) { FactoryGirl.create(:user_with_group) }
    it "creates and update a request" do
      EvmSpecHelper.local_miq_server
      expect(AuditEvent).to receive(:success).with(
        :event        => "service_template_provision_request_created",
        :target_class => "ServiceTemplate",
        :userid       => admin.userid,
        :message      => "Service_Template_Provisioning requested by <#{admin.userid}> for ServiceTemplate:#{service_template.id}"
      )

      # creates a request

      # the dialogs populate this
      values = {:src_id => service_template.id}

      request = described_class.make_request(nil, values, admin.userid) # TODO: nil

      expect(request).to be_valid
      expect(request).to be_a_kind_of(described_class)
      expect(request.request_type).to eq("clone_to_service")
      expect(request.description).to eq("Provisioning Service [#{service_template.name}] from [#{service_template.name}]")
      expect(request.requester).to eq(admin)
      expect(request.userid).to eq(admin.userid)
      expect(request.requester_name).to eq(admin.name)

      # updates a request

      expect(AuditEvent).to receive(:success).with(
        :event        => "service_template_provision_request_updated",
        :target_class => "ServiceTemplate",
        :userid       => alt_user.userid,
        :message      => "Service_Template_Provisioning request updated by <#{alt_user.userid}> for ServiceTemplate:#{service_template.id}"
      )
      described_class.make_request(request, values, alt_user.userid)
    end
  end
end
