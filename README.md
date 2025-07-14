# ASN Service Utils

## IMPORTANT
This is a subproject and contains utils only.

## Description
ASN (AI-Driving Secure Networking) is a distributed framework of secure network functions.\
This API package is shared by all ASN services built as plugins.
To build an ASN Distributed Service, you can refer to `asn-service-template` to get started.\
The latest version is `v25.7.0`.

## API Layout
    ├── builder       // Makefiles and Dockerfiles needed to build `YOUR_SERVICE`
    ├── config        // config files needed to deploy `ASN` and `YOUR_SERVICE`
    ├── docker        // docker compose files needed to deploy `ASN` and `YOUR_SERVICE`
    ├── proto         // ASN's manager proto
    └── go.mod        // dependencies used by `ASN`

## How to use the API
1. Implement all functions in controller.ASNController in `YOUR_SERVICE` controller module.
   This is API provided by `YOUR_SERVICE` and called by ASN controller.
2. Provide the init controller function
   ```
       func NewASNServiceController() controller.ASNServiceController
   ```
   in `YOUR_SERVICE` controller module.
   The function name, parameter and return type should be EXACTLY THE SAME with the function above.
   This is used for ASN controller to recognize `YOUR_SERVICE` controller.
   ASNController is an interface defined in `./controller/asn.go`.
   ASNServiceController is an interface defined in `./controller/service.go`.
3. Implement all functions in servicenode.ASNService in `YOUR_SERVICE` servicenode module.
   This is the API provided by `YOUR_SERVICE` and called by ASN service node.
4. Provide the init service node function
   ```
       func NewASNService(asnServiceNode ASNServiceNode) (servicenode.ASNService, error)
   ```
   in `YOUR_SERVICE`'s service node module.
   The function name, parameter and return type should be EXACTLY THE SAME with the function above.
   This is used for ASN service node to recognize `YOUR_SERVICE` node.
   ASNServiceNode is an interface defined in `./servicenode/asn.go`.
   ASNService is an interface defined in `./servicenode/service.go`.
5. Finish `YOUR_SERVICE` code. Use the function defined in `ASNController` and `ASNServiceNode` instead to manage the relation between `YOUR_SERVICE` controller and servicenode.

## How to compile `YOUR_SERVICE`
1. Check the version of ASN API is corresponding with the version in ASN and `YOUR_SERVICE`.
2. Check the dependency in `./go.mod`.
   If you use the dependency list there, make sure the version is EXACTLY THE SAME one.
   If you are building multiple plugins in one system, make sure the dependency they use have no different version.
3. Git submodule `asn-service-api` in `YOUR_SERVICE` and export SERVICE_API_PATH = `YOUR SUBMODULE PATH`
4. Include `./scripts/builder/Makefile` in `YOUR_SERVICE` Makefile
5. Provide "make build" command in `YOUR_SERVICE` Makefile
6. Run `make compile-plugin` and can get the build directory like
    ```
        build
        ├── controller    
            ├── YOUR_SERVICE_NAME.so 
            └── conf
        └── servicenode
            ├── YOUR_SERVICE_NAME.so 
            └── conf
    ```
7. Move `controller/[YOUR_SERVICE].so` file to your ASN controller plugins directory
   and `servicenode/[YOUR_SERVICE].so` file to your ASN servicenode plugins directory.

## Deploy
1. To deploy `YOUR_SERVICE` as one controller and one service node structure, just refer to `./scripts/docker`.
   Make your project as the structure below
   ```
       project name
       ├── controller    
           ├── config
           ├── services
               └── YOUR_SERVICE_NAME.so 
           └── asnc.yml
       └── servicenode
           ├── config
           ├── services
               └── YOUR_SERVICE_NAME.so 
           └── asnsn.yml
   ```
   Then, use docker compose to start both controller and service node server.
2. To deploy `YOUR_SERVICE` as one controller and multiple service nodes structure.
   Run the scripts in the `./scripts/docker-cluster`.
   This will generate the file similar to the structure as `./scripts/docker`.
   Move the `.so` files under plugins directory and then use docker compose to start the service.
3. To deploy `YOUR_SERVICE` in your own topology. Please carefully read the Introduction in `ASN.25`.
   Move your `*-topology.json` file under `project name/controller/config`.
   Move the `.so` files under plugins directory. Then can use docker compose to start the service.
