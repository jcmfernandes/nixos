output "public_ip" {
  description = "Public IPv4 of the builder VM."
  value       = oci_core_instance.vivivi.public_ip
}

output "private_ip" {
  description = "Private IP of the builder VM."
  value       = oci_core_instance.vivivi.private_ip
}

output "ssh_command" {
  description = "Ready-to-paste SSH invocation for the builder."
  value       = "ssh ubuntu@${oci_core_instance.vivivi.public_ip}"
}

output "attic_s3_access_key" {
  description = "S3 access key ID for the Attic service."
  value       = ionoscloud_s3_key.attic.id
}

output "attic_s3_secret_key" {
  description = "S3 secret access key for the Attic service. Paste into vivivi's atticd_env sops secret."
  value       = ionoscloud_s3_key.attic.secret_key
  sensitive   = true
}
