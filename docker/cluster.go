// Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

type ASNC struct {
	Log         Log                `yaml:"log"`
	DB          DBPair             `yaml:"db"`
	Iam         Iam                `yaml:"iam"`
	Grpc        GRPC               `yaml:"grpc"`
	Restful     ASNCRestful        `yaml:"restful"`
	Network     Network            `yaml:"network"`
	ServiceNode ServiceNode        `yaml:"servicenode"`
	Service     map[string]Service `yaml:"service"`
}

type ASNCRestful struct {
	Port uint16 `yaml:"port"`
}

type Log struct {
	Demo   bool      `yaml:"demo"`
	Prefix string    `yaml:"prefix"`
	ALog   LogConfig `yaml:"api_log"`
	RLog   LogConfig `yaml:"runtime_log"`
	ELog   LogConfig `yaml:"entity_log"`
	PLog   LogConfig `yaml:"perf_log"`
}

type LogConfig struct {
	FileName string `yaml:"filename"`
	Level    string `yaml:"level"`
}

type DB struct {
	Host     string `yaml:"host"`
	Port     string `yaml:"port"`
	Database string `yaml:"database_name"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
}

type DBPair struct {
	MongoDB  DB `yaml:"mongodb"`
	InfluxDB DB `yaml:"influxdb"`
}

type Iam struct {
	Provider string `yaml:"provider"`
	Host     string `yaml:"host"`
	Port     string `yaml:"port"`
	TLS      bool   `yaml:"tls"`
	CaCert   string `yaml:"ca_cert"`
	CertPem  string `yaml:"cert_pem"`
	KeyPem   string `yaml:"key_pem"`
}

type Network struct {
	Id          string `yaml:"id"`
	TopoFile    string `yaml:"topo_file"`
	TokenSecret string `yaml:"token_secret"`
}

type GRPC struct {
	Port uint64 `yaml:"port"`
}

type ServiceNode struct {
	KeepAlive int `yaml:"keepalive"`
}

type Service struct {
	AutoStart bool           `yaml:"auto_start"`
	Version   ServiceVersion `yaml:"version"`
	DB        DBPair         `yaml:"db"`
}

type ServiceVersion struct {
	Min string `yaml:"min"`
	Max string `yaml:"max"`
}

type MyNetwork struct {
	NetworkID   string     `json:"network_id"`
	NetworkName string     `json:"network_name"`
	Topology    []Topology `json:"topology"`
}

type Topology struct {
	NodeName       string   `json:"node_name"`
	NodeType       string   `json:"nodeType"`
	Location       Location `json:"location"`
	Label          string   `json:"label"`
	ExternalLinked []string `json:"external_linked"`
	SubNodes       []Node   `json:"sub_nodes"`
}

type Location struct {
	Coordinates Coordinate `json:"coordinates"`
	Address     string     `json:"address"`
}

type Coordinate struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type Node struct {
	NodeName       string   `json:"node_name"`
	NodeType       string   `json:"nodeType"`
	Location       Location `json:"location"`
	Label          string   `json:"label"`
	ExternalLinked []string `json:"external_linked"`
	InternalLinked []string `json:"internal_linked"`
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
	Ports         []string          `yaml:"ports,omitempty"`
	Volumes       []string          `yaml:"volumes,omitempty"`
	Command       string            `yaml:"command,omitempty"`
	DependsOn     []string          `yaml:"depends_on,omitempty"`
}

type Volume struct {
	Driver string `yaml:"driver,omitempty"`
}

type ASNSN struct {
	Log        Log               `yaml:"log"`
	General    General           `yaml:"general"`
	Controller Controller        `yaml:"controller"`
	Tsdb       TSDB              `yaml:"tsdb"`
	Service    SNService         `yaml:"service"`
	NetIf      map[string]string `yaml:"netif"`
}

type General struct {
	Mode            string `yaml:"mode"`
	ID              string `yaml:"id"`
	NetworkPath     string `yaml:"network_path"`
	NodeName        string `yaml:"node_name"`
	Type            string `yaml:"type"`
	NetworkCapacity int    `yaml:"network_capacity"`
	CliPort         int    `yaml:"cli_port"`
}

type Controller struct {
	IP            string `yaml:"ip"`
	Port          int    `yaml:"port"`
	RetryInterval int    `yaml:"retry_interval"`
	TokenSecret   string `yaml:"token_secret"`
}

type TSDB struct {
	Type     string `yaml:"type"`
	Name     string `yaml:"name"`
	IP       string `yaml:"ip"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
}

type SNService struct {
	ConfigTimeout int `yaml:"config_timeout"`
}

func main() {
	var n int
	var err error
	if len(os.Args) != 2 {
		log.Println("args error, using default value: 100")
		n = 1
	} else {
		n, err = strconv.Atoi(os.Args[1])
		if err != nil {
			log.Println("args error, using default value: 100")
			n = 1
		}
	}

	// generate controller file
	err = os.MkdirAll("controller", 0755)
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

	asnConf := ASNC{
		Log: Log{
			Demo:   true,
			Prefix: "asn",
			ALog: LogConfig{
				FileName: "api.log",
				Level:    "info",
			},
			RLog: LogConfig{
				FileName: "runtime.log",
				Level:    "info",
			},
			ELog: LogConfig{
				FileName: "entity.log",
				Level:    "info",
			},
			PLog: LogConfig{
				FileName: "perf.log",
				Level:    "info",
			},
		},
		DB: DBPair{
			MongoDB: DB{
				Host:     "localhost",
				Port:     "27017",
				Database: "asn",
				Username: "amia",
				Password: "2022",
			},
			InfluxDB: DB{
				Host:     "localhost",
				Port:     "8086",
				Database: "asn",
				Username: "amia",
				Password: "2022",
			},
		},
		Iam: Iam{
			Provider: "sapphire",
			Host:     "localhost",
			Port:     "17930",
			TLS:      false,
			CaCert:   "/etc/asnc/cert/ca-cert",
			CertPem:  "/etc/asnc/cert/cert-pem",
			KeyPem:   "/etc/asnc/cert/key-pem",
		},
		Grpc: GRPC{50051},
		Restful: ASNCRestful{
			Port: 58080,
		},
		Network: Network{
			Id:          "network1",
			TopoFile:    "/etc/asnc/config/100nodes-topology.json",
			TokenSecret: "asn-example-token-secret/FIXME_when_deploy",
		},
		ServiceNode: ServiceNode{3},
		Service: map[string]Service{
			"myservice": {
				AutoStart: false,
				Version: ServiceVersion{
					Min: "v2.2.0",
					Max: "v2.2.0",
				},
				DB: DBPair{
					MongoDB: DB{
						Host:     "localhost",
						Port:     "27017",
						Database: "asn",
						Username: "amia",
						Password: "2022",
					},
					InfluxDB: DB{
						Host:     "localhost",
						Port:     "8086",
						Database: "asn",
						Username: "amia",
						Password: "2022",
					},
				},
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

	cliConf := map[string]string{
		"server": "localhost",
		"port":   "50051",
		"token":  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NDcwMTk0NDUsInVzZXJuYW1lIjoiYXNuLXN1cGVydmlzb3IifQ.8UlBi9qlL3NxXYllKp3NN2WUBwSs4Q1sqKvfMk3MRwI",
	}
	cliYaml, err := yaml.Marshal(cliConf)
	if err != nil {
		panic(err)
	}
	err = os.WriteFile("controller/config/cli.conf", cliYaml, 0644)
	if err != nil {
		panic(err)
	}

	// You can decide the topology network
	network := MyNetwork{
		NetworkID:   "network1",
		NetworkName: "Network with 100 nodes",
		Topology:    []Topology{},
	}

	for i := 1; i <= n; i++ {
		location := Location{
			Coordinates: Coordinate{
				Latitude:  -90.0 + rand.Float64()*180,
				Longitude: -180.0 + rand.Float64()*360,
			},
			Address: fmt.Sprintf("%d street", i),
		}
		network.Topology = append(network.Topology, Topology{
			NodeName:       fmt.Sprintf("node%d", i),
			NodeType:       "networkNode",
			Location:       location,
			Label:          "CORE",
			ExternalLinked: []string{},
			SubNodes: []Node{{
				NodeName:       fmt.Sprintf("switch%d", i),
				NodeType:       "switch",
				Location:       location,
				Label:          "CORE",
				ExternalLinked: []string{},
				InternalLinked: []string{},
			}},
		})
	}

	bytes, err := json.MarshalIndent(network, "", "  ")
	if err != nil {
		panic(err)
	}

	fileName := "controller/config/100nodes-topology.json"
	err = os.WriteFile(fileName, bytes, 0644)
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
		Image:         "mongo:7.0",
		Restart:       "always",
		Ulimits: map[string]int{
			"nofile": 100000,
		},
		Environment: map[string]string{
			"MONGO_INITDB_ROOT_USERNAME": "amia",
			"MONGO_INITDB_ROOT_PASSWORD": "2022",
		},
		Ports:   []string{"27017:27017"},
		Volumes: []string{"./data/:/data/db"},
		Command: "--bind_ip_all --auth",
	}
	asncD.Services["asn-idb"] = DockerService{
		ContainerName: "asn-idb",
		Image:         "influxdb:2.7",
		Ports:         []string{"8086:8086"},
		Environment: map[string]string{
			"INFLUXDB_DB":             "asn",
			"INFLUXDB_ADMIN_USER":     "amia",
			"INFLUXDB_ADMIN_PASSWORD": "2022",
			"INFLUXDB_USER":           "amia",
			"INFLUXDB_USER_PASSWORD":  "2022",
		},
	}
	asncD.Services["sapphire-iam"] = DockerService{
		ContainerName: "sapphire-iam",
		Image:         "registry.amiasys.com/sapphire.iam:25.6.4",
		Restart:       "always",
		Privileged:    true,
		DependsOn:     []string{"asn-mdb"},
		Ports:         []string{"17930:17930", "17931:17931"},
		Volumes: []string{
			"./iam-cert/:/usr/local/sapphire/conf/",
			"./iam-config/:/usr/local/sapphire/",
			"./iam-log/iam/:/var/log/iam/",
		},
	}
	asncD.Services["asnc"] = DockerService{
		Image:       "registry.amiasys.com/asnc:25.7.8",
		Restart:     "always",
		DependsOn:   []string{"asn-mdb", "asn-idb", "sapphire-iam"},
		NetworkMode: "host",
		Volumes: []string{
			"./asn-cert/:/asn/cert",
			"./asn-config/:/asn/config",
			"./asn-log/asn/:/var/log/asn/controller",
			"./asn-services:/usr/local/asn/controller/services",
			"./asn-web:/var/www/asnc/",
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

	err = os.MkdirAll("servicenode/service", 0755)
	if err != nil {
		panic(err)
	}

	for i := 1; i <= n; i++ {
		fileName = fmt.Sprintf("sn%d", i)
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

		asnC := ASNSN{
			Log: Log{
				Prefix: "asn",
				ALog: LogConfig{
					FileName: "api.log",
					Level:    "info",
				},
				RLog: LogConfig{
					FileName: "runtime.log",
					Level:    "info",
				},
				ELog: LogConfig{
					FileName: "entity.log",
					Level:    "info",
				},
				PLog: LogConfig{
					FileName: "perf.log",
					Level:    "info",
				},
			},
			General: General{
				Mode:            "cluster",
				ID:              "",
				NetworkPath:     fmt.Sprintf("network1.node%d.switch%d", i, i),
				NodeName:        fmt.Sprintf("switch%d", i),
				Type:            "server",
				NetworkCapacity: 1024,
				CliPort:         50052,
			},
			Controller: Controller{
				IP:            "172.17.0.1",
				Port:          50051,
				RetryInterval: 5,
				TokenSecret:   "asn-example-token-secret/FIXME_when_deploy",
			},
			Tsdb: TSDB{
				Type:     "influxdbv1",
				Name:     "asn-dev",
				IP:       "172.17.0.1",
				Port:     8086,
				Username: "amia",
				Password: "2022",
			},
			Service: SNService{
				ConfigTimeout: 20,
			},
			NetIf: map[string]string{
				"data":       "eth0",
				"control":    "eth0",
				"management": "eth0",
			},
		}
		asnCFYaml, err := yaml.Marshal(asnC)
		if err != nil {
			panic(err)
		}
		err = os.WriteFile(fmt.Sprintf("servicenode/%s/config/asn.conf", fileName), asnCFYaml, 0644)
		if err != nil {
			panic(err)
		}

		asnD := asncDocker{
			Services: map[string]DockerService{
				"asnsn": {
					Image:         "registry.amiasys.com/asnsn:25.7.8",
					ContainerName: fmt.Sprintf("network-node%d-switch%d", i, i),
					Restart:       "always",
					Volumes: []string{
						"./config/:/asn/config",
						"./log/:/var/log/asnsn/",
						"../service:/usr/local/asn/servicenode/services/",
					},
				}},
		}
		asnDY, err := yaml.Marshal(asnD)
		if err != nil {
			panic(err)
		}
		err = os.WriteFile(fmt.Sprintf("servicenode/%s/asnsn.yml", fileName), asnDY, 0644)
		if err != nil {
			panic(err)
		}
	}

	shellUp := `#!/bin/bash
# 进入 controller 文件夹并启动 Docker Compose
cd controller || { echo "Failed to enter controller folder"; exit 1; }
echo "Starting Docker Compose in controller folder..."
docker compose -f asnc.yml up -d || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Docker Compose started in controller folder."
cd - || { echo "Failed to return to the previous directory"; exit 1; }
# 进入 servicenode 文件夹并逐个启动 sn1 到 sn100
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }
for i in $(seq 1 100); do
folder="sn$i"
if [ -d "$folder" ]; then
cd "$folder" || { echo "Failed to enter $folder folder"; exit 1; }
echo "Starting Docker Compose in $folder..."
docker compose -f asnsn.yml up -d || { echo "Failed to execute docker compose in $folder"; exit 1; }
echo "Docker Compose started in $folder."
cd - >/dev/null || { echo "Failed to return to servicenode folder"; exit 1; }
else
echo "Folder $folder does not exist, skipping."
fi
done
echo "All tasks completed."`

	if err := os.WriteFile("up.sh", []byte(shellUp), 0755); err != nil {
		panic(err)
	}

	shellDown := `#!/bin/bash
cd controller || { echo "Failed to enter controller folder"; exit 1; }
echo "Starting Docker Compose in controller folder..."
docker compose -f asnc.yml down || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Docker Compose started in controller folder."
cd - || { echo "Failed to return to the previous directory"; exit 1; }
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }
for i in $(seq 1 100); do
folder="sn$i"
if [ -d "$folder" ]; then
cd "$folder" || { echo "Failed to enter $folder folder"; exit 1; }
echo "Starting Docker Compose in $folder..."
docker compose -f asnsn.yml down || { echo "Failed to execute docker compose in $folder"; exit 1; }
echo "Docker Compose started in $folder."
cd - >/dev/null || { echo "Failed to return to servicenode folder"; exit 1; }
else
echo "Folder $folder does not exist, skipping."
fi
done
echo "All tasks completed."`
	if err := os.WriteFile("down.sh", []byte(shellDown), 0755); err != nil {
		panic(err)
	}

	ymlIam := `# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

## Log Configurations
#log:
#  level: "info" # Supported log level: panic | fatal | error | warning | info | debug | trace. Default: info
#  file: "/var/log/sapphire/iam.log" # Default: "/var/log/sapphire/iam.log"

## Database Configurations
#db:
#  provider: "mongodb" # Supported: "mongodb" | "filedb". Default: "mongodb"
#  url: "localhost:27017" # Default: "localhost:27017"
#  username: "amia" # Default: "amia"
#  password: "2022" # Default: "2022"

## LDAP Configurations
#ldap:
#  enabled: false # Default: false
#  interval: 15 # Sync interval in minutes, Default: 15
#  url: "ldap://localhost:389" # Default: "ldap://localhost:389"
#  base_dn: "dc=amianetworks,dc=com" # Default: "dc=amianetworks,dc=com"
#  password_cn: "cn=admin" # Default: "cn=admin"
#  password: "2022" # Default: "2022"
#  mapping:
#    account: # other fields will be added to descriptions, name will be filled to cn and sn by default
#      ou: "account" # Default: "account"
#      name: "uid" # Default: "uid"
#      password: "userPassword" # Default: "userPassword"
#      email: "mail" # Default: "mail"
#      phone: "telephoneNumber" # Default: "telephoneNumber"
#      description:
#        id: "id" # Default: "id"
#        created_at: "createdAt" # Default: "createdAt"
#        updated_at: "updatedAt" # Default: "updatedAt"
#        type: "type" # Default: "type"
#        totp: "totp" # Default: "totp"
#        mfa_config: "mfaConfig" # Default: "mfaConfig"
#        metadata: "metadata" # Default: "metadata"
#    group: # other fields will be added to descriptions
#      ou: "group" # Default: "group"
#      name: "cn" # Default: "cn"
#      accounts: "member" # Default: "member"
#      description:
#        id: "id" # Default: "id"
#        created_at: "createdAt" # Default: "createdAt"
#        updated_at: "updatedAt" # Default: "updatedAt"
#        metadata: "metadata" # Default: "metadata"

## API Configurations
#api:
#  grpc:
#    port: 17930 # gRPC API port. Default:17930
#    tls:
#      root_ca: "/etc/sapphire/cert/ca.crt" # Default: "/etc/sapphire/cert/ca.crt"
#      pem_file: "/etc/sapphire/cert/server.pem" # Default: "/etc/sapphire/cert/server.pem"
#      key_file: "/etc/sapphire/cert/server.key" # Default: "/etc/sapphire/cert/server.key"

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
#        - "2023"
#      dbs:
#        - 0 # index: 0 ~ 15 (Default: 0)

## Email Service
#smtp: # SMTP email server config
#  enabled: false # Default: false
#  tls: true
#  host: "smtp.office365.com"
#  email: "email@amiasys.com"
#  username: "email@amiasys.com"
#  password: ""
#  port: 587

## Account Configurations
#account:
#  special_key: "SpecialAccount@AmiaNetworks2025"
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
#  # You can recover the account through email or SMS(TBD).
#  # If none of the above methods are available, the admin can reset the account through the cli command line.
#  # TBD: recover account by SMS
#  recovery:
#    email: # Sending a code to your recovery email # Code format:  "^[0-9a-zA-Z-:.]{6,128}$"
#      expire: 5 # Expiration time in minutes. Default 5 minutes.
#      resend_interval: 1 # Resending interval in minutes. Default 1 minute

## Authentication Configurations
#authentication:
#  service:
#    client_ca: "/etc/sapphire/cert/ca.crt"
#    name: "^[0-9a-zA-Z_-]{2,36}$"
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
#  # TBD: SMS
#  mfa:
#    totp:
#      # The issuer indicates the provider or service this account is associated with, URL-encoded according to RFC 3986.
#      issuer: "Amianetworks"

## Authorization Configurations
#authorization:
#  # JWT（JSON Web Token）is an open source standard (RFC 7519) that defines the format for how communicating parties can exchange information securely.
#  # TBD: JWT provides different token strategies for different entity types
#  jwt:
#    issuer: "amianetworks.com"
#    # RS256 Key Set for JWT signature.
#    # [NOT RECOMMENDED!!!] If either is set to empty, a random set will be used.
#    public_key_file: ""
#    private_key_file: ""
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
`
	if err := os.WriteFile("controller/config/iam.yml", []byte(ymlIam), 0644); err != nil {
		panic(err)
	}
}
