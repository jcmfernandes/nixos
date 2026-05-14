# Pick the first AD; A1.Flex availability varies, the apply will tell us if
# we need to retry in another region/AD ("Out of host capacity").
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Latest Ubuntu 24.04 ARM image compatible with the A1.Flex shape.
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Networking: one VCN, one public subnet, IGW, default route, security list
# allowing inbound SSH from var.ssh_allowed_cidr.
resource "oci_core_vcn" "vivivi" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "${var.instance_name}-vcn"
  dns_label      = "builder"
}

resource "oci_core_internet_gateway" "vivivi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vivivi.id
  display_name   = "${var.instance_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "vivivi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vivivi.id
  display_name   = "${var.instance_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.vivivi.id
  }
}

resource "oci_core_security_list" "vivivi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vivivi.id
  display_name   = "${var.instance_name}-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.ssh_allowed_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "vivivi" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.vivivi.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "${var.instance_name}-subnet"
  dns_label         = "subnet"
  route_table_id    = oci_core_route_table.vivivi.id
  security_list_ids = [oci_core_security_list.vivivi.id]
}

resource "oci_core_instance" "vivivi" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.A1.Flex"
  display_name        = var.instance_name

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vivivi.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = data.http.ssh_keys.response_body
  }
}

data "http" "ssh_keys" {
  url = var.ssh_keys_url
}
