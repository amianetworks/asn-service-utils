// Copyright 2026 Amiasys Corporation and/or its affiliates. All rights reserved.

package main

import (
	"fmt"
	"log"
	"os"
	"strconv"
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
			"influxdb_data": {Driver: "local"},
			"ldap_slap":     {Driver: "local"},
			"ldap_data":     {Driver: "local"},
		},
	}
	asncD.Services["asn-mdb"] = DockerService{
		ContainerName: "asn-mdb",
		Image:         "mongo:8",
		Restart:       "unless-stopped",
		Ulimits: map[string]int{
			"nofile": 100000,
			"nproc":  65535,
		},
		Environment: map[string]string{
			"MONGO_INITDB_ROOT_USERNAME": "amia",
			"MONGO_INITDB_ROOT_PASSWORD": "${ASNC_MONGO_ROOT_PASSWORD:?set ASNC_MONGO_ROOT_PASSWORD}",
		},
		NetworkMode: "host",
		Volumes:     []string{"./data/:/data/db"},
		Command:     "--bind_ip_all --auth",
	}
	asncD.Services["asn-idb"] = DockerService{
		ContainerName: "asn-idb",
		Image:         "influxdb:2.7",
		NetworkMode:   "host",
		Environment: map[string]string{
			"DOCKER_INFLUXDB_INIT_MODE":        "setup",
			"DOCKER_INFLUXDB_INIT_USERNAME":    "amia",
			"DOCKER_INFLUXDB_INIT_PASSWORD":    "${ASNC_INFLUXDB_ADMIN_PASSWORD:?set ASNC_INFLUXDB_ADMIN_PASSWORD}",
			"DOCKER_INFLUXDB_INIT_ORG":         "amia",
			"DOCKER_INFLUXDB_INIT_BUCKET":      "asn",
			"DOCKER_INFLUXDB_INIT_ADMIN_TOKEN": "${ASNC_INFLUXDB_ADMIN_TOKEN:?set ASNC_INFLUXDB_ADMIN_TOKEN}",
			"DOCKER_INFLUXDB_INIT_RETENTION":   "0",
		},
		Volumes: []string{"influxdb_data:/var/lib/influxdb2"},
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
		Image:         "registry.amiasys.com/sapphire.iam:26.7.8",
		NetworkMode:   "host",
		Restart:       "unless-stopped",
		Privileged:    true,
		DependsOn:     []string{"asn-mdb", "asn-idb", "asn-rdb"},
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
		Image:       "registry.amiasys.com/asnc:26.7.5",
		Restart:     "unless-stopped",
		DependsOn:   []string{"asn-mdb", "asn-idb", "asn-rdb", "sapphire-iam"},
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
			Image:         "registry.amiasys.com/asnsn:26.7.5",
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
services_provisioned: [ asn, myservice ]

## Mode
# In dev mode, all verification codes will be returned directly through API, and the default log level will be "debug".
mode: dev # pro | dev, Default: pro

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
#db:
#  provider: "mongodb" # Supported: "mongodb" | "filedb". Default: "mongodb"
#  url: "localhost:27017" # Default: "localhost:27017"
#  username: "amia" # Default: "amia"
#  password: "REPLACE_WITH_SECRET" # Default: generated secret

## Email Service
#smtp: # SMTP email server config
#  enabled: false # Default: false
#  expire : 5 # in minutes, Default: 5
#  resend_interval: 1 # in minutes, Default: 1
#  tls: true
#  host: "smtp.office365.com"
#  email: "email@amiasys.com"
#  username: "email@amiasys.com"
#  password: ""
#  port: 587

## Phone Service
#phone:
#  enabled: false # Default: false
#  expire : 5 # in minutes, Default: 5
#  resend_interval: 1 # in minutes, Default: 1
#  services:
#    86: # if multiple country codes are using the same config, use comma to separate them, i.e., 86,852,853
#      provider: "aliyun" # "tencent" || "aliyun"
#      app_id: ""
#      app_secret: "" # not needed for tencent
#      secret_id: "" # not needed for aliyun
#      secret_key: "" # not needed for aliyun
#      sign_name: ""
#      template_id: "" # for SMS verification code
#    1: # if multiple country codes are using the same config, use comma to separate them, i.e., 86,852,853
#      provider: "tencent" # "tencent" || "aliyun"
#      app_id: ""
#      app_secret: "" # not needed for tencent
#      secret_id: "" # not needed for aliyun
#      secret_key: "" # not needed for aliyun
#      sign_name: ""
#      template_id: "" # for SMS verification code

## Sign In with Apple
#apple:
#  asn:
#    - "xxx.xxx.xxx" # bundle ID
#    - "xxx.xxx.xxx" # bundle ID
#  swan:
#    - "xxx.xxx.xxx" # bundle ID
#    - "xxx.xxx.xxx" # bundle ID
#  scarlette:
#    - "xxx.xxx.xxx" # bundle ID
#    - "xxx.xxx.xxx" # bundle ID

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

## LDAP Configurations
#ldap:
#  enabled: false # Default: false
#  interval: 15 # Sync interval in minutes, Default: 15
#  url: "ldap://localhost:389" # Default: "ldap://localhost:389"
#  base_dn: "dc=amianetworks,dc=com" # Default: "dc=amianetworks,dc=com"
#  password_cn: "cn=admin" # Default: "cn=admin"
#  password: "REPLACE_WITH_SECRET" # Default: generated secret
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
#      urls:
#        - "localhost:6379" # Default: "localhost:6379"
#      passwords:
#        - "REPLACE_WITH_SECRET"
#      dbs:
#        - 0 # index: 0 ~ 15 (Default: 0)

## Log Configurations
#log:
#  level: "info" # panic | fatal | error | warning | info | debug | trace. Default: pro: info, dev: debug
#  file: "/var/log/sapphire/iam.log" # Default: "/var/log/sapphire/iam.log"

## Account Configurations
#account:
#  special_key: "REPLACE_WITH_SECRET" # Used to create special accounts which skips MFA.
#  password_algo: sha1 # argon2id | bcrypt | md5 | pbkdf2 | scrypt | sha1 | sha256 | sha512, Default: sha256. CAUTION: more demanding algorithms like argon2id are not recommended in VMs.
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
#    name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"
#    password: "^[0-9a-zA-Z!@$._-]{6,128}$"
#    email: "^(?:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})?$"
#    country_code: "^(?:\\d{1,3})?$"
#    phone: "^(?:$|[\\d\\s\\-\\(\\)\\.]{6,15})$"
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
#
#  access_control:
#    format:
#      role:
#        name: "^[0-9a-zA-Z!@$._-]{6,128}$"
#      policy:
#        name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"
#        scope: "^[0-9a-zA-Z!@$._-/*?%&]{6,128}$"
#        operation: "^[0-9a-zA-Z!@$._-]{6,128}$"
#        time: "^[0-9a-zA-Z-:.]{6,128}$"

## Group Configurations
#group:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"

## Role Configurations
#role:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"

## Policy Configurations
#policy:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"

## Testing Configurations
# Caution: This part should only be configured when testing.
#testing:
#  apple_token_secret: "REPLACE_WITH_SECRET"
#  wechat_bypass_server: true
`
	if err := os.WriteFile("controller/config/iam.yml", []byte(ymlIam), 0644); err != nil {
		panic(err)
	}
}
