terraform {
  backend "remote" {
    organization = "hjgames"
    workspaces {
      name = "hetzner"
    }
  }
}

# Hetzner

provider "hcloud" {
  version = "~> 1.22"
}

resource "hcloud_server" "ai-banana" {
  name         = "ai-banana"
  image        = "ubuntu-20.04"
  server_type  = "cx11"
  location     = "nbg1"
  ssh_keys     = [hcloud_ssh_key.jasper.id]
  backups      = false
  firewall_ids = [hcloud_firewall.ai-banana.id]
  user_data    = <<-EOT
    #!/bin/sh
    curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-20.03 bash 2>&1 | tee /tmp/infect.log
    EOT

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "hcloud_volume" "volume1" {
  name = "volume1"
  # After changing the disk size, ssh into the machine and run:
  #     $ resize2fs /dev/sdb
  size     = 250
  location = "nbg1"
  format   = "ext4"
}

resource "hcloud_volume_attachment" "volume1" {
  volume_id = hcloud_volume.volume1.id
  server_id = hcloud_server.ai-banana.id
  automount = false
}

resource "hcloud_ssh_key" "jasper" {
  name       = "Jaspers key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "hcloud_firewall" "ai-banana" {
  name = "ai-banana"

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "2022"
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "2022"
  }

  # Resilio
  rule {
    direction  = "in"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "18776"
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "18776"
  }

  # Tailscale
  rule {
    direction  = "in"
    protocol   = "udp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "41641"
  }
}

# Cloudflare

provider "cloudflare" {
  version = "~> 2.0"
}

resource "cloudflare_record" "ai-banana" {
  zone_id = data.cloudflare_zones.ai-banana.zones[0].id
  name    = "ai-banana"
  value   = hcloud_server.ai-banana.ipv4_address
  type    = "A"
  ttl     = 300
}

resource "cloudflare_record" "banana" {
  zone_id = data.cloudflare_zones.ai-banana.zones[0].id
  name    = "banana"
  value   = "ai-banana.jasperwoudenberg.com"
  type    = "CNAME"
  ttl     = 300
}

data "cloudflare_zones" "ai-banana" {
  filter {
    name = "jasperwoudenberg.com"
  }
}
