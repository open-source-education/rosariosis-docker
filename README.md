# RosarioSis

RosarioSIS Student Information System for school management. 

Sincronized with latest official version:  **v10.6.3**

More details here https://github.com/francoisjacquet/rosariosis


## Requirements

- Docker
- Docker Compose


## Get Latest mysql dump

```sh
docker-compose -f docker-compose-dev.yml up -d  --build
```
- Go to `http://localhost/InstallDatabase.php` and follow the wizard install steps
- After that, you will have the database ready to export

These steps are required when a new official version is released

## Run

```
docker-compose up -d --build
```

**Note**

This mode is just for test or very limited and basic infraestructure. For advanced usage, read [this](https://github.com/open-source-education/rosariosis-docker/wiki/Advanced-Docker)

## Login

Go to your browser and open this url `http://localhost`.

If you are using the **ready to use mode**, you should see something like this:

![login](https://user-images.githubusercontent.com/3322836/211174049-1e69af0b-71c1-49ea-af19-8185aa8bbb03.png)

Use the default credentials:
- user: admin
- password: RLG#bxhHwHs@7*sw