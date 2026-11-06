// Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

package main

import (
	"fmt"
	"log"
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

type ASNC struct {
	Mode    string    `yaml:"mode"`
	API     API       `yaml:"api"`
	Admin   Admin     `yaml:"admin"`
	Network Network   `yaml:"network"`
	Service []Service `yaml:"service"`
}

type API struct {
	GrpcM string `yaml:"grpc_m"`
}

type Admin struct {
	CreateWhenStart bool `yaml:"create_when_start"`
}

type Network struct {
	TopoFile string `yaml:"topo_file"`
}

type Service struct {
	Name   string `yaml:"name"`
	Plugin string `yaml:"plugin"`
}

type asncDocker struct {
	Services map[string]DockerService `yaml:"services"`
	Volumes  map[string]Volume        `yaml:"volumes,omitempty"`
}

type DockerService struct {
	ContainerName string            `yaml:"container_name,omitempty"`
	Image         string            `yaml:"image,omitempty"`
	Privileged    bool              `yaml:"privileged,omitempty"`
	Restart       string            `yaml:"restart,omitempty"`
	Ulimits       map[string]int    `yaml:"ulimits,omitempty"`
	Environment   map[string]string `yaml:"environment,omitempty"`
	NetworkMode   string            `yaml:"network_mode,omitempty"`
	// Ports         []string          `yaml:"ports,omitempty"`
	Volumes   []string `yaml:"volumes,omitempty"`
	Command   string   `yaml:"command,omitempty"`
	DependsOn []string `yaml:"depends_on,omitempty"`
}

type Volume struct {
	Driver string `yaml:"driver,omitempty"`
}

type ASNSN struct {
	General    General    `yaml:"general"`
	Controller Controller `yaml:"controller"`
}

type General struct {
	Mode     string `yaml:"mode"`
	NodeName string `yaml:"node_name"`
	Type     string `yaml:"type"`
}

type Controller struct {
	Address string `yaml:"address"`
}

func main() {
	var n int
	var err error
	if len(os.Args) != 2 {
		log.Println("args error, using default value: 1")
		n = 1
	} else {
		n, err = strconv.Atoi(os.Args[1])
		if err != nil {
			log.Println("args error, using default value: 1")
			n = 1
		}
	}

	// generate controller file
	err = os.MkdirAll("controller", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/cert", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/config", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/log", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/services", 0755)
	if err != nil {
		panic(err)
	}

	asnConf := ASNC{
		Mode: "dev",
		API: API{
			GrpcM: "localhost:12766",
		},
		Admin: Admin{
			CreateWhenStart: true,
		},
		Network: Network{},
		Service: []Service{
			{
				Name:   "myservice",
				Plugin: "myservice.so",
			},
		},
	}

	asnYaml, err := yaml.Marshal(asnConf)
	if err != nil {
		panic(err)
	}
	err = os.WriteFile("controller/config/asn.conf", asnYaml, 0644)
	if err != nil {
		panic(err)
	}

	asncD := asncDocker{
		Services: map[string]DockerService{},
		Volumes: map[string]Volume{
			"postgres_data": {Driver: "local"},
			"ldap_slap":     {Driver: "local"},
			"ldap_data":     {Driver: "local"},
		},
	}
	// The controller's stores: PostgreSQL 18 with TimescaleDB; the image creates
	// the timescaledb extension in POSTGRES_DB. Sapphire IAM uses it too.
	asncD.Services["asn-pdb"] = DockerService{
		ContainerName: "asn-pdb",
		Image:         "timescale/timescaledb:latest-pg18",
		Restart:       "unless-stopped",
		NetworkMode:   "host",
		Environment: map[string]string{
			"POSTGRES_USER":     "amia",
			"POSTGRES_PASSWORD": "${ASNC_POSTGRES_PASSWORD:?set ASNC_POSTGRES_PASSWORD}",
			"POSTGRES_DB":       "asn",
		},
		Volumes: []string{"postgres_data:/var/lib/postgresql"},
		Ulimits: map[string]int{
			"nofile": 100000,
			"nproc":  65535,
		},
	}
	asncD.Services["asn-rdb"] = DockerService{
		ContainerName: "asn-rdb",
		Image:         "redis:8",
		Restart:       "unless-stopped",
		NetworkMode:   "host",
		Command:       "redis-server --save --appendonly yes --requirepass 2022 --port 6379 --bind 0.0.0.0",
		Ulimits: map[string]int{
			"nofile": 100000,
			"nproc":  65535,
		},
	}
	asncD.Services["sapphire-iam"] = DockerService{
		ContainerName: "sapphire-iam",
		Image:         "registry.amiasys.com/sapphire.iam:27.0.0",
		NetworkMode:   "host",
		Restart:       "unless-stopped",
		Privileged:    true,
		DependsOn:     []string{"asn-pdb", "asn-rdb"},
		Volumes: []string{
			"./cert/:/etc/sapphire/cert/",
			"./config/:/etc/sapphire/config/",
			"./log/iam/:/var/log/iam/",
		},
		Ulimits: map[string]int{
			"nofile": 100000,
			"nproc":  65535,
		},
	}
	asncD.Services["asnc"] = DockerService{
		Image:       "registry.amiasys.com/asnc:26.25.6",
		Restart:     "unless-stopped",
		DependsOn:   []string{"asn-pdb", "asn-rdb", "sapphire-iam"},
		NetworkMode: "host",
		Ulimits: map[string]int{
			"nofile": 100000,
			"nproc":  65535,
		},
		Volumes: []string{
			"./config/:/etc/asn/controller/config",
			"./log/asn/:/var/log/asn/controller",
			"./services:/usr/local/asn/controller/services",
		},
	}

	asncYaml, err := yaml.Marshal(asncD)
	if err != nil {
		panic(err)
	}
	err = os.WriteFile("controller/asnc.yml", asncYaml, 0644)
	if err != nil {
		panic(err)
	}

	// make service node file
	err = os.MkdirAll("servicenode", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("servicenode/services", 0755)
	if err != nil {
		panic(err)
	}

	asnD := asncDocker{
		Services: map[string]DockerService{},
	}

	for i := 1; i <= n; i++ {
		fileName := fmt.Sprintf("sn%d", i)
		err = os.MkdirAll("servicenode/"+fileName, 0755)
		if err != nil {
			panic(err)
		}

		err = os.MkdirAll(fmt.Sprintf("servicenode/%s/config", fileName), 0755)
		if err != nil {
			panic(err)
		}

		err = os.MkdirAll(fmt.Sprintf("servicenode/%s/log", fileName), 0755)
		if err != nil {
			panic(err)
		}

		asnSN := ASNSN{
			General: General{
				Mode:     "cluster",
				NodeName: fmt.Sprintf("server%d", i),
				Type:     "server",
			},
			Controller: Controller{
				Address: "127.0.0.1:12762",
			},
		}
		asnSNFYaml, err := yaml.Marshal(asnSN)
		if err != nil {
			panic(err)
		}
		err = os.WriteFile(fmt.Sprintf("servicenode/%s/config/asn.conf", fileName), asnSNFYaml, 0644)
		if err != nil {
			panic(err)
		}

		asnD.Services[fmt.Sprintf("asnsn-%d", i)] = DockerService{
			Image:         "registry.amiasys.com/asnsn:26.25.6",
			ContainerName: fmt.Sprintf("asnsn-%d", i),
			NetworkMode:   "host",
			Environment: map[string]string{
				"GOMAXPROCS": "1",
			},
			Volumes: []string{
				fmt.Sprintf("./%s/config/:/etc/asn/servicenode/config", fileName),
				fmt.Sprintf("./%s/log/:/var/log/asn/servicenode/", fileName),
				"./services:/usr/local/asn/servicenode/services/",
			},
		}
	}

	asnDY, err := yaml.Marshal(asnD)
	if err != nil {
		panic(err)
	}
	err = os.WriteFile("servicenode/asnsn.yml", asnDY, 0644)
	if err != nil {
		panic(err)
	}

	shellUp := `#!/bin/bash

# 定义并发批次大小
# Controller 部分
cd controller || { echo "Failed to enter controller folder"; exit 1; }
echo "Starting Docker Compose in controller folder..."
docker compose -f asnc.yml up -d || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Docker Compose started in controller folder."
cd - || { echo "Failed to return to the previous directory"; exit 1; }

# 进入 servicenode 文件夹
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }

echo "Starting service nodes..."

# 启动
(set -o pipefail; COMPOSE_PARALLEL_LIMIT=100 docker compose -f asnsn.yml up -d 2>&1 | sed '/Creating/d; /Starting/d') || { echo "Failed to execute docker compose in servicenode folder"; exit 1; }
echo "All tasks completed."`

	if err := os.WriteFile("up.sh", []byte(shellUp), 0755); err != nil {
		panic(err)
	}

	shellDown := `#!/bin/bash

# 1. 先进入 servicenode 目录停止 Service Nodes
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }

echo "Stopping service nodes (asnsn.yml)..."
(set -o pipefail; COMPOSE_PARALLEL_LIMIT=100 docker compose -f asnsn.yml down 2>&1 | sed '/Stopping/d; /Removing/d') || { echo "Failed to execute docker compose in servicenode folder"; exit 1; }
echo "Service nodes stopped."

# 重要：返回上一级目录，确保后续能正确找到 controller 文件夹
cd - || { echo "Failed to return to the previous directory"; exit 1; }

# 2. 再进入 controller 目录停止 Controller
cd controller || { echo "Failed to enter controller folder"; exit 1; }

echo "Stopping Docker Compose in controller folder..."
docker compose -f asnc.yml down || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Controller stopped."

echo "All tasks completed."`
	if err := os.WriteFile("down.sh", []byte(shellDown), 0755); err != nil {
		panic(err)
	}

	ymlIam := `# Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

###
# Services
#
# Services
# Mode
# API
# DB
# Email Server
# LDAP
# Lock
# Log
#
# Account
# Authentication
# Authorization
# Group
# Role
# Policy
#
# Testing

## Services
services_provisioned: [ asn, swan, scarlette ]

## Mode
# In dev mode, all verification codes will be returned directly through API, and the default log level will be "debug".
#mode: pro # pro | dev, Default: pro

## API Configurations
#api:
#  grpc:
#    port: 50426 # gRPC API port. Default:50426
#    tls:
#      enabled: false # Default: false
#      root_ca: "/etc/sapphire/cert/client-ca.crt"
#      pem_file: "/etc/sapphire/cert/server.pem"
#      key_file: "/etc/sapphire/cert/server.key"

## Database Configurations
# IAM shares the controller's PostgreSQL database (asn-pdb) as its own schemas.
db:
  provider: "postgres" # Supported: "postgres" (PostgreSQL 18) | "mongodb" | "filedb". Default: "postgres"
  url: "localhost:5432/asn" # postgres: host:port/<database>[?options]
  username: "amia"
  password: "REPLACE_WITH_SECRET" # the asn-pdb password (ASNC_POSTGRES_PASSWORD)
  name: "iam" # IAM database name, a schema; each service uses "<name>_<service>"

## Email Service
mail: # Email service used to deliver verification codes
  enabled: false # Default: false
  # Only the keys of the selected type are read; the others are carried unread,
  # so a deployment can switch back and forth by editing "type" alone.
  provider:
    type: "smtp" # Supported: "smtp" | "graph". Default: "smtp"
    # For SMTP. Required when enabled: host, port, email.
    tls: true # false skips verification of the relay's certificate (test relays only). Whether TLS is used at all follows the port.
    host: "smtp.office365.com"
    email: "email@amiasys.com"
    username: "email@amiasys.com" # what authenticates; usually the same address
    password: ""
    port: 587
    # For Graph. Required when enabled: tenant_id, client_id, certificate, mailbox.
    # The registered application holds the Mail.Send APPLICATION permission, which
    # reaches every mailbox in the tenant until an application access policy scopes
    # it to the mailbox below. That policy is configured in the tenant.
    tenant_id: "REPLACE_WITH_TENANT_ID"
    client_id: "REPLACE_WITH_APPLICATION_ID"
    certificate: "/etc/sapphire/cert/mailer.cert.pem" # PEM or legacy PKCS#12
    private_key: "/etc/sapphire/cert/mailer.key.pem" # Leave out when one file holds both. An encrypted PEM key is not supported.
    certificate_password: "" # PKCS#12 only. Default: none
    mailbox: "noreply.swanarc@amianetworks.com" # the Exchange Online mailbox to send as
  # Sender display name per service. It is what a recipient sees beside the address,
  # and it titles the subject and the body, so a code sent for one product does not
  # introduce itself as another. A service listed nowhere here sends as "IAM".
  nicknames:
    - service: "swan"
      nickname: "SwanArc"

## Verification Codes
#
# How long a code lives and how often one is sent, the same for SMS and email.
# These were set under "mail" and "phone" before; a value still set there must
# match the one here, or IAM does not start.
verification_code:
  expire: 5 # in minutes, Default: 5
  # Resend interval uses exponential backoff based on outcome, per recipient.
  # After success: interval = resend_success_base * resend_amp_factor^successCount, capped at resend_success_max.
  # After failure: interval = resend_failure_base * resend_amp_factor^failureCount, capped at resend_failure_max.
  # A success resets the failure count.
  resend_success_base: 10    # in seconds, post-success cooldown base. Default: 10
  resend_failure_base: 30    # in seconds, per-send/failure penalty base. Default: 30
  resend_amp_factor: 2       # exponential amplification factor. Default: 2
  resend_success_max: 120    # in seconds, cap for success-side cooldown. Default: 120
  resend_failure_max: 3600   # in seconds, cap for failure-side penalty. Default: 3600
  resend_failure_decay: 3600 # in seconds, time per failure-count level decayed when idle. 0 = no decay. Default: 3600
  resend_success_decay: 86400 # in seconds, time per success-count level decayed when idle. 0 = no decay. Default: 86400

## Phone Service
#
# There are three modes for displaying phone country codes:
# - all: all countries are displayed;
# - include: only countries in the list are displayed;
# - exclude: all countries except those in the list are displayed.
#
#phone:
#  enabled: false # Default: false
#  country_code:
#    mode: all # all | include | exclude, Default: all
#    codes: ["86", "852", "1"] # Default: []
#  services:
#    86: # if multiple country codes are using the same config, use comma to separate them, i.e., 86,852,853
#      provider: "aliyun" # "tencent" || "aliyun" || "twilio"
#      app_id: "" # for Twilio, use Verify Service SID
#      app_secret: "" # Aliyun only
#      secret_id: "" # Tencent: Secret ID; Twilio: Account SID
#      secret_key: "" # Tencent: Secret Key; Twilio: Auth Token
#      sign_name: "" # Aliyun and Tencent needed
#      template_id: "" # Aliyun and Tencent needed
#      from: "18773124359" # Aliyun outside 86 only: the sender ID or number. Default: 18773124359
#    1: # if multiple country codes are using the same config, use comma to separate them, i.e., 86,852,853
#      provider: "tencent" # "tencent" || "aliyun" || "twilio"
#      app_id: "" # for Twilio, use Verify Service SID
#      app_secret: "" # Aliyun only
#      secret_id: "" # Tencent: Secret ID; Twilio: Account SID
#      secret_key: "" # Tencent: Secret Key; Twilio: Auth Token
#      sign_name: "" # Aliyun and Tencent needed
#      template_id: "" # Aliyun and Tencent needed

## Records of the verification codes sent in pro mode: to whom, when, through which provider and
## what it answered, never the code. Kept in the IAM database, in verification_code_message and
## verification_code_delivery. Disabled, codes go straight to the providers and nothing is kept.
#code_records:
#  enabled: true # Default: true
#  retention: 0 # in days, 0 keeps them forever. Default: 0

## Sign In with Apple
#apple:
#  asn:
#    bundle_ids:
#      - "xxx.xxx.xxx" # bundle ID
#      - "xxx.xxx.xxx" # bundle ID
#    callback:
#      android:
#        package_name: "xxx.xxx.xxx" # package name
#        host: "asnAppleLogin" # android:host
#        scheme: "asnAppleLogin" # android:scheme
#  swan:
#    bundle_ids:
#      - "xxx.xxx.xxx" # bundle ID
#      - "xxx.xxx.xxx" # bundle ID
#    callback:
#      android:
#        package_name: "xxx.xxx.xxx" # package name
#        host: "swanAppleLogin" # android:host
#        scheme: "swanAppleLogin" # android:scheme
#  scarlette:
#    bundle_ids:
#      - "xxx.xxx.xxx" # bundle ID
#      - "xxx.xxx.xxx" # bundle ID
#    callback:
#      android:
#        package_name: "xxx.xxx.xxx" # package name
#        host: "scarletteAppleLogin" # android:host
#        scheme: "scarletteAppleLogin" # android:scheme

## Sign In with Google
#google:
#  asn:
#    client_ids:
#      - "xxx.xxx.xxx" # client ID
#      - "xxx.xxx.xxx" # client ID
#  swan:
#    client_ids:
#      - "xxx.xxx.xxx" # client ID
#      - "xxx.xxx.xxx" # client ID
#  scarlette:
#    client_ids:
#      - "xxx.xxx.xxx" # client ID
#      - "xxx.xxx.xxx" # client ID

## WeChat
#wechat:
#  asn:
#    appID1: appSecret1
#    appID2: appSecret2
#  swan:
#    appID1: appSecret1
#    appID2: appSecret2
#  scarlette:
#    appID1: appSecret1
#    appID2: appSecret2

# Passkey
#
# Passkey is used for WebAuthn registration and authentication.
#passkey:
#  asn:
#    server_domains: [ "asn.amiasys.com" ] # Leave empty to disable Passkey registration / verification.
#    display_name: "ASN" # Default: service name
#    extra_allowed_origins: [] # By default, "https://"+server_domain is allowed for each server domain. If additional origins are needed, add them here.
#    timeouts:
#      login: 300 # session expiration in seconds, Default: 300
#      registration: 300 # session expiration in seconds, Default: 300
#  swan:
#    server_domains: [ "swan.amiasys.com" ] # Leave empty to disable Passkey registration / verification.
#    display_name: "SWAN" # Default: service name
#    extra_allowed_origins: [ ] # By default, "https://"+server_domain is allowed for each server domain. If additional origins are needed, add them here.
#    timeouts:
#      login: 300 # session expiration in seconds, Default: 300
#      registration: 300 # session expiration in seconds, Default: 300
#  scarlette:
#    server_domains: [ "scarlette.amiasys.com" ] # Leave empty to disable Passkey registration / verification.
#    display_name: "Scarlette" # Default: service name
#    extra_allowed_origins: [ ] # By default, "https://"+server_domain is allowed for each server domain. If additional origins are needed, add them here.
#    timeouts:
#      login: 300 # session expiration in seconds, Default: 300
#      registration: 300 # session expiration in seconds, Default: 300

## LDAP Configurations
#ldap:
#  enabled: false # Default: false
#  interval: 15 # Sync interval in minutes, Default: 15
#  url: "ldap://localhost:389" # Default: "ldap://localhost:389"
#  base_dn: "dc=amianetworks,dc=com" # Default: "dc=amianetworks,dc=com"
#  password_cn: "cn=admin" # Default: "cn=admin"
#  password: "REPLACE_WITH_SECRET" # Default: "2022"
#  ous:
#    account: "People"
#    group: "Group"

# Lock
#
# Default mode is standalone.
# To config "distributed" mode, uncomment "redis" config section.
#   - Redis "standard" is a single-instance locker
#   - Redis "redlock" is used to implement distributed locks with multiple Redis instance.
#lock:
#  mode: "standalone" # (standalone | distributed) Default: "standalone"
#  waiting_limit: 10 # Default: 10 (Seconds)
#  holding_limit: 5 # Default: 5 (Seconds)
#  redis: # used only in distributed mode
#    mode: "standard" # (standard | redlock) Default: "standard"
#    nodes: # list of redis nodes. Only the first one is used in standard mode
#      - url: "localhost:6379" # Default: "localhost:6379"
#        passwords: "2023"
#        dbs: 0 # index: 0 ~ 15 (Default: 0)

## Log Configurations
#log:
#  level: "info" # panic | fatal | error | warning | info | debug | trace. Default: pro: info, dev: debug
#  file: "/var/log/sapphire/iam.log" # Default: "/var/log/sapphire/iam.log"

## Account Configurations
#account:
#  special_key: "REPLACE_WITH_SECRET" # Used to create special accounts which skips MFA.
#  password_algo: sha256 # argon2id | bcrypt | md5 | pbkdf2 | scrypt | sha1 | sha256 | sha512, Default: sha256. CAUTION: more demanding algorithms like argon2id are not recommended in VMs.
#  rename: false # whether renaming an account's username is allowed. Default: false
#
#  # Username must be unique system wide, and it is the default identifier for login.
#  # Other fields, like email and phone number, can also be used as login identifier, as soon as explicitly set below.
#  # However, Sapphire only enforce the uniqueness at creatation of an account. Declaring a field as unique here doesn't
#  # guarantee the uniqueness of existing values of this field. Sapphire won't allow login with non-unique values.
#  unique_fields:
#    email: true # Default: true
#    phone: true # Default: true
#
#  # Regular expressions are used here to specify the format of username, password, and user group.
#  # ^, $: start-of-line and end-of-line respectively.
#  # [...]: Accept ANY ONE of the character within the square bracket, e.g., [aeiou] matches "a", "e", "i", "o" or "u".
#  # [.-.] (Range Expression): Accept ANY ONE of the character in the range, e.g., [0-9] matches any digit; [A-Za-z] matches any uppercase or lowercase letters.
#  # {m,n}: m to n (both inclusive)
#  # If you need to customize the format, please refer to the regular expression syntax.
#  format:
#    name: "^[0-9a-zA-Z_.-]{2,36}$"
#    password: "^[0-9a-zA-Z!@$._-]{6,128}$"
#    email: "^(?:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})?$"
#
#  # Provisioning Rules at Account Creation
#  # Though all accounts are unique in the system, the service may not share users by default.
#  # At creation of an account FROM a service, Sapphire checks the provisioning rules below.
#  # Rules related to a service which is not provisioned will be ignored.
#  provisioning_rules: # The following rules will be applied to provision accounts across services:
#    # add all asn/viewer_group users to swan/swan_ug_default
#    - from:
#        service: asn
#        user_groups: [ viewer_group ]
#      to:
#        - service: swan
#          user_groups: [ swan_ug_default ]
#
#    # add all swan/{admin,network_admin} to scarlette/network_viewer
#    - from:
#        service: swan
#        user_groups: [ admin, network_admin ]
#      to:
#        - service: scarlette
#          user_groups: [ network_viewer ]

## Authentication Configurations
#authentication:
#  service:
#    mtls: false # Default: false
#    client_ca: "/etc/sapphire/cert/client-ca.crt"
#    name: "^[0-9a-zA-Z_.-]{2,36}$"
#
#  # Attempt frequency can limit the frequency of user attempts to log in.
#  attempt_frequency:
#    wait_min: 1 # Minimum wait time after an attempt in second. Default: 1 Seconds
#    wait_max: 43200 # Maximum waiting time after an attempt in second. Default: 43200 Seconds
#    amp_factor: 2 # The waiting time after each failure will be extended according to the amplification factor. Default: 3
#    mfa: 5 # Default: 5
#    code_max_attempts: 0 # Wrong codes a verification code takes before a new one is needed. 0 = no limit. Default: 0
#
#  # Config the concurrent authentication to limit the number of concurrent authentication entity allowed per user.
#  # You can configure the maximum number of entities allowed to log in, and if exceeded, it will be handled according to the auto replacement policy.
#  # Supported auto replacement policies: disable | random | oldest | latest. Default: disable
#  concurrent_authentication:
#    entity_allowed: 3 # maximum number of entities allowed, 0 means disable;  less than 0 means login is prohibited. Default: 3
#    auto_replacement: "disable"
#
#  # Configure MFA(Multi-Factor Authentication) information
#  # By using the TOTP(Time-Based One Time Password) method, one time password is created on the user side through a smartphone application.
#  # Applications that are known to work with TOTP： Microsoft Authenticator、Google Authenticator）
#  mfa:
#    totp:
#      # The issuer indicates the provider or service this account is associated with, URL-encoded according to RFC 3986.
#      issuer: "Amia Networks Inc."
#
#  # Device-Related Configurations
#  # If enabled == false, or a limit is set to negative, device-related configurations will be ignored (unlimited).
#  device_limit:
#    enabled: true # Whether to enable device limit. Default: true
#    eviction_mode: "inactive" # none | inactive | any. None means no eviction, inactive means only inactive devices are evicted, any means any device can be evicted. Default: inactive
#    total: -1 # The total number of login devices allowed per user. Default: -1
#    phone: -1 # The number of login devices under this category allowed per user. Default: -1
#    tablet: -1 # The number of login devices under this category allowed per user. Default: -1
#    wearable: -1 # The number of login devices under this category allowed per user. Default: -1
#    browser: -1 # The number of login devices under this category allowed per user. Default: -1
#    mini_program: -1 # The number of login devices under this category allowed per user. Default: -1
#    pc: -1 # The number of login devices under this category allowed per user. Default: -1
#    unknown: -1 # The number of login devices under this category allowed per user. Default: -1
#
#  # Password flow (forgot-password recovery and in-session change) configuration.
#  password_reset:
#    ttl: 10 # Flow token lifetime in minutes. Default: 10
#    max_attempts: 5 # Failed verification attempts before the flow token is invalidated. Default: 5
#
#  # Auth flow (stateful login credential phase) configuration.
#  auth_flow:
#    ttl: 10 # Credential-phase flow token lifetime in minutes. Default: 10
#    max_attempts: 5 # Failed verification attempts before the flow token is invalidated. Default: 5
#
#  # Session delegation: exchanging a live session for a one-time ticket that a second
#  # device redeems into a session of its own (app -> browser hand-off, or a device that
#  # cannot practically log in on its own). Disabled by default: delegation widens the
#  # blast radius of a single stolen session, so it must be opted into deliberately.
#  delegation:
#    enabled: false # Whether to allow session delegation. Default: false
#    ticket_expire: 60 # Ticket lifetime in SECONDS (not minutes) - it only has to survive one hop. Default: 60
#    max_expire: 120 # Longest lifetime in minutes any delegated session may be granted. Non-positive means the parent session's own ceiling is the only limit. Default: 120
#    allow_refresh: false # Whether a delegated session may be granted a refresh token. Without one it dies at its access token expiry and cannot be renewed. Default: false
#    # Default lifetime in minutes per device category of the REDEEMING device, used when
#    # the caller does not request one. 0 falls back to authorization.jwt.access.expire.
#    # Every value is still clamped by max_expire and by the parent session's own ceiling.
#    default_expire:
#      phone: 0
#      tablet: 0
#      wearable: 0
#      browser: 0
#      mini_program: 0
#      pc: 0
#      unknown: 0
#
#  # How often (in seconds) the server flushes its batch of revoked access tokens to
#  # connected clients over the ClientConnect stream. Lower = revocations propagate
#  # faster but more frequent pushes. Non-positive falls back to 1. Default: 1
#  revoke_sync_interval: 1

## Authorization Configurations
#authorization:
#  # JWT（JSON Web Token）is an open source standard (RFC 7519) that defines the format for how communicating parties can exchange information securely.
#  # TBD: JWT provides different token strategies for different entity types
#  jwt:
#    issuer: "amianetworks.com"
#    # RS256 Key Set for JWT signature.
#    # [NOT RECOMMENDED!!!] If either is set to empty, a random set will be used.
#    public_key_file: "" # Default: /etc/sapphire/cert/jwt.pem (can be auto-generated)
#    private_key_file: "" # Default: /etc/sapphire/cert/jwt.key (can be auto-generated)
#    access_token:
#      expire: 60   # Access token expiration time in minutes. Default: 60 minutes.
#    refresh_token:
#      enabled: true # Support automatically obtaining access token through refresh token. Default: true
#      expire: 600  # Refresh token expiration time in minutes. Default: 600 minutes.

## Group Configurations
#group:
#  name: "^[0-9a-zA-Z_.-]{2,36}$"
#  # The following apply when a group is created with a prefix/suffix instead of an
#  # exact name. The generated name is "<prefix><separator><token><separator><suffix>",
#  # with empty parts and their separators omitted, and it must still match "name".
#  affix: "^[0-9a-zA-Z_.-]{0,16}$" # pattern the prefix and suffix must match
#  separator: "-"                  # joins prefix, token and suffix
#  token_length: 8                 # length of the generated random token
#  max_attempts: 5                 # retries when a generated name is already taken

## Role Configurations
#role:
#  name: "^[0-9a-zA-Z_.-]{2,36}$"

## Policy Configurations
#policy:
#  name: "^[0-9a-zA-Z_.-]{2,36}$"

## Testing Configurations
# Caution: This part should only be configured when testing.
#testing:
#  apple_token_secret: "REPLACE_WITH_SECRET"
#  google_token_secret: "REPLACE_WITH_SECRET"
#  wechat_bypass_server: true
`
	if err := os.WriteFile("controller/config/iam.yml", []byte(ymlIam), 0644); err != nil {
		panic(err)
	}
}
