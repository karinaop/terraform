terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

provider "azurerm" {
    skip_provider_registration = true
    features {
    }
}

resource "azurerm_resource_group" "groupresource-k" {
  name     = "groupresource-kes22"
  location = "East US"
}

resource "azurerm_virtual_network" "virtualnetwork-k" {
  name                = "virtualNetwork1"
  location            = azurerm_resource_group.groupresource-k.location
  resource_group_name = azurerm_resource_group.groupresource-k.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "subnet-k" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.groupresource-k.name
  virtual_network_name = azurerm_virtual_network.virtualnetwork-k.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "publicip-k" {
  name                = "acceptanceTestPublicIp1"
  resource_group_name = azurerm_resource_group.groupresource-k.name
  location            = azurerm_resource_group.groupresource-k.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_security_group" "securitygp-k" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.groupresource-k.location
  resource_group_name = azurerm_resource_group.groupresource-k.name

      security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

  tags = {
    environment = "Production"
  }
}
resource "azurerm_network_interface" "ninterface-k" {
  name                = "nic-k"
  location            = azurerm_resource_group.groupresource-k.location
  resource_group_name = azurerm_resource_group.groupresource-k.name

  ip_configuration {
    name                          = "nic-ip-k"
    subnet_id                     = azurerm_subnet.subnet-k.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.publicip-k.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic-sgp-k" {
  network_interface_id      = azurerm_network_interface.ninterface-k.id
  network_security_group_id = azurerm_network_security_group.securitygp-k.id
}

resource "azurerm_virtual_machine" "mysql-k" {
  name                  = "mysql-vm"
  location            = azurerm_resource_group.groupresource-k.location
  resource_group_name = azurerm_resource_group.groupresource-k.name
  network_interface_ids = [azurerm_network_interface.ninterface-k.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}

data "azurerm_public_ip" "ip-db" {
  name                = azurerm_public_ip.publicip-k.name
  resource_group_name = azurerm_resource_group.groupresource-k.name
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_virtual_machine.mysql-k]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "testadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip-db.ip_address
        }
        source = "mysql"
        destination = "/home/testadmin"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "testadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip-db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7 mysql-client",
            "sudo mysql < /home/testadmin/mysql/script/user.sql",
            "sudo cp -f /home/testadmin/mysql/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}
