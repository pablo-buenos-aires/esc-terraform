
# output "account_id" { value = data.aws_caller_identity.me.account_id }
output "arn"        { value = data.aws_caller_identity.me.arn } # вывод параметров ресурса
output "region_here"     { value = data.aws_region.here.region } # и региона
# output "region_from_vpc"     { value = module.vpc.region}

output "private_subnet_ids" {  value = module.vpc.private_subnet_ids }
output "public_ip"    { value = module.ec2.public_ip }

output "asg_name"   { value =  module.ec2.asg_name }
output "asg_arn"    { value = module.ec2.asg_arn }

output "instance_profile_name_ec2" { value = module.ec2.instance_profile_name }

# output "public_instance_id"  { value = aws_instance.pub_ubuntu.id } # id инстанса
# output "private_instance_id_1"  { value = aws_instance.priv_ubuntu_1.id } # id инстанса 2
# output "private_instance_id_2"  { value = aws_instance.priv_ubuntu_2.id } # id инстанса 2

output "public_dns"   { value = module.ec2.public_dns } # DNS

output "public_instance_id" { value = module.ec2.public_instance_id }
output "nat_network_interface_id" { value = module.ec2.nat_network_interface_id }
