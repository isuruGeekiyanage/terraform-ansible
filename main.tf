
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
 
terraform {
  required_providers {
    ansible = {
      version = "~> 1.2.0"
      source  = "ansible/ansible"
    }
  } 
}

resource "azurerm_public_ip" "azure_public_ip" {
  name                = "ksft-public-ip"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  allocation_method   = "Dynamic" 
  sku                 = "Basic"  

  tags = {
    environment = "Development"
  }
}


data "azurerm_public_ip" "azure_public_ip" {
  name                = azurerm_public_ip.azure_public_ip.name
  resource_group_name = azurerm_linux_virtual_machine.azure_virtual_machine.resource_group_name
}

resource "azurerm_resource_group" "azure_resource_group" {
  name     = "example-resources-ksft-01"
  location = "West Europe"
  tags = {
    environment = "Development"
    createdBy   = "Asanka Gayashan"
    note        = "Do not delete"
  }
}

resource "azurerm_virtual_network" "azure_virtual_network" {
  name                = "ksft-vfc-virtual-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_subnet" "azure_subnet" {
  name                 = "ksft-vfc-subnet"
  resource_group_name  = azurerm_resource_group.azure_resource_group.name
  virtual_network_name = azurerm_virtual_network.azure_virtual_network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "azure_network_interface" {
  name                = "ksft-vfc-nic"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name

  ip_configuration {
    name                          = "ksft-vfc-internal"
    subnet_id                     = azurerm_subnet.azure_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.azure_public_ip.id 

  }
}

resource "azurerm_linux_virtual_machine" "azure_virtual_machine" {
  resource_group_name   = azurerm_resource_group.azure_resource_group.name
  location              = azurerm_resource_group.azure_resource_group.location
  name                  = "ksft-linux"
  network_interface_ids = [azurerm_network_interface.azure_network_interface.id]
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  disable_password_authentication = true 

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }


  os_disk {
    name                 = "ksft-linux-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "ansible_host" "host" {
  name   = data.azurerm_public_ip.azure_public_ip.ip_address
  groups = ["nginx"]

  variables = {
    ansible_user                 = "adminuser",
    ansible_ssh_private_key_file = "~/.ssh/id_rsa",
    ansible_python_interpreter   = "/usr/bin/python3"
    yaml_secret                  = local.decoded_vault_yaml.sensitive
  }
}

resource "ansible_vault" "secrets" {
  vault_file          = "vault.yml"
  vault_password_file = "password"
}


locals {
  decoded_vault_yaml = yamldecode(ansible_vault.secrets.yaml)
}

