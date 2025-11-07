output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "web_private_ip" {
  value = module.web_ec2[1].private_ip
}

output "rds_address" {
  value     = module.db.db_instance_address
  sensitive = false
}

output "alb_dns_name" {
  value     = module.alb.dns_name
}
