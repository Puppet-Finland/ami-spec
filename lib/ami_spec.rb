require 'ami_spec/aws_instance'
require 'ami_spec/server_spec'

module AmiSpec
  # == Parameters:
  # amis::
  #   A hash of roles and amis in the format of:
  #   {role => ami_id}. i.e.
  #   {'web_server' => 'ami-abcd1234'}
  # specs::
  #   A string of the directory to find ServerSpecs.
  #   There should be a folder in this directory for each role found in ::amis
  # subnet_id::
  #   The subnet_id to start instances in.
  # key_name::
  #   The SSH key name to assign to instances. This key name must exist on the executing host for passwordless login.
  # key_file::
  #   The SSH key file to use to connect to the host.
  # aws_options::
  #   A hash of AWS options. Possible values are:
  #   - region (defaults to AWS_DEFAULT_REGION)
  #   - security_group_ids (defaults to the default security group for the VPC)
  #   - instance_type (defaults to t2.micro)
  #   - public_ip (defaults to false)
  # ssh_user::
  #   The username to SSH to the AMI with.
  # == Returns:
  # Boolean - The result of all the server specs.
  def self.run(amis:, specs:, subnet_id:, key_name:, key_file:, aws_options: {}, ssh_user:, debug: false)
    instances = []

    amis.each_pair do |role, ami|
      instances.push(
        AwsInstance.start(
          role: role,
          ami: ami,
          subnet_id: subnet_id,
          key_name: key_name,
          options: aws_options,
        )
      )
    end



    results = []
    instances.each do |ec2|
      ip = aws_options[:public_ip] ? ec2.public_ip_address : ec2.private_ip_address
      wait_for_ssh(ip: ip, user: ssh_user, key_file: key_file)
      results.push(
        ServerSpec.run(
          instance: ec2,
          spec: specs,
          private_ip: aws_options[:private_ip],
          user: ssh_user,
          key_file: key_file,
        )
      )
    end

    results.all?
  ensure
    instances.each do |ec2|
      begin
        ec2.terminate unless debug
      rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
        # Ignore since some instances may not have started/been created
      end
    end
  end

  def self.wait_for_ssh(ip:, user:, key_file:)
    retries = 30
    while retries > 1
      begin
        Net::SSH.start(ip, user, keys: [key_file], timeout: 5) { |ssh| ssh.exec 'echo boo!'}
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Timeout::Error
        # Do nothing
      else
        break
      end
      retries = retries - 1
    end
  end
end
