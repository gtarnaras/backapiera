SHELL := /bin/bash
CORE_FILE=infra/docker-compose.yml
SRC_DIR=framework
CONF_DIR=infra

API_BUILD_DIR=infra/api
API_NAME=decdriver-framework
VERSION=1.134.0

HAMMER=hammer.sh
HAMMER_DIR=hammer

HELPER_BUILD_DIR=ci/helper
HELPER_NAME=decdriver-helper

DOCKER_REPO=artifactory.t.cit.corp.hmrc.gov.uk:5558/als-images

# This will output the help for each task
.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

################################
####   MANAGEMENT COMMANDS  ####
################################

.PHONY: pull
pull:  ## Pull all services
	docker-compose -f $(CORE_FILE) pull || true

.PHONY: up
up: clean-docker create-dirs ## Start/Restart all services
	docker-compose -f $(CORE_FILE) kill
	docker-compose -f $(CORE_FILE) up -d

.PHONY: clean
clean: clean-docker clean-docker-volumes ## Clean up the application and delete docker volume
	docker-compose -f $(CORE_FILE) kill

.PHONY: run
run: kill start ## Install the application

.PHONY: hooks
hooks: ## Setup local git hooks
	pip3 install pre-commit autopep8
	cp ./ci/hooks/* .git/hooks/
	pre-commit install

.PHONY: stats
stats: ## Show code stats
	pip3 install pygount
	$(shell echo `date` > docs/loc)
	pygount --format=summary >> docs/loc

.PHONY: docs
docs: ## Setup local git hooks
	pip3 install pycco
	pycco framework/**/*.py -p
	pycco framework/conf/* -p
	pycco framework/**/**/**/*.py -p

.PHONY: start
start: ## Trigger the services
	docker-compose -f $(CORE_FILE) up -d

.PHONY: all
all: clean build run test-local ## Clean, build and start the app

.PHONY: kill
kill: ## Stop all services
	docker-compose -f $(CORE_FILE) kill

################################
####     BUILD COMMANDS     ####
################################

.PHONY: build
build: ## Build the container
	docker build $(DOCKER_HOST_NET) --build-arg BUILD_VER=$(VERSION) -f $(API_BUILD_DIR)/Dockerfile -t $(DOCKER_REPO)/$(API_NAME):latest .

.PHONY: build-helper
build-helper: ## Build the helper container
	docker build $(DOCKER_HOST_NET) -f $(HELPER_BUILD_DIR)/Dockerfile -t $(DOCKER_REPO)/decdriver-helper:latest .

.PHONY: build-nc
build-nc: ## Build the container without caching
	docker build --no-cache $(DOCKER_HOST_NET) --build-arg BUILD_VER=$(VERSION) -f $(API_BUILD_DIR)/Dockerfile -t $(DOCKER_REPO)/$(API_NAME):latest .

.PHONY: test-local
test-local: ## Submit dec to local env
	cd ./$(SRC_DIR)/$(HAMMER_DIR) && ./$(HAMMER) local

.PHONY: test-test
test-test: ## Submit dec to test env
	cd ./$(SRC_DIR)/$(HAMMER_DIR) && ./$(HAMMER) test

.PHONY: test-live
test-live: ## Submit dec to live env
	cd ./$(SRC_DIR)/$(HAMMER_DIR) && ./$(HAMMER) live

################################
####     PUBLISH COMMANDS   ####
################################

# import publish config
# You can change the default deploy config with `make cnf="deploy_special.env" release`
dpl ?= ${CONF_DIR}/deploy.env
include $(dpl)
export $(shell sed 's/=.*//' $(dpl))[[]]

release: clean build-nc publish ## Make a release by building and publishing
publish: repo-login publish-latest publish-version ## Docker publish both tags: versioned and latest

.PHONY: repo-login
repo-login: ## Login to Artifactory
	docker login -u $(ARTIFACTORY_USER) -p $(ARTIFACTORY_API_KEY) $(DOCKER_REPO)

.PHONY: publish-latest
publish-latest: ## Publish the `latest` tagged container to Docker repo
	@echo 'publish latest to $(DOCKER_REPO)'
	docker push $(DOCKER_REPO)/$(API_NAME):latest

.PHONY: publish-helper
publish-helper: ## Publish the `latest` tagged helper container to Docker repo
	@echo 'publish latest to $(DOCKER_REPO)'
	docker push $(DOCKER_REPO)/decdriver-helper:latest

.PHONY: publish-version
publish-version: tag-version ## Publish the `{version}` tagged container to Docker repo
	@echo 'publish $(VERSION) to $(DOCKER_REPO)'
	docker push $(DOCKER_REPO)/$(API_NAME):$(VERSION)

tag: tag-version ## Generate container tags for the `{version}` and `latest` tags

.PHONY: tag-version
tag-version: ## Generate container with a versioned tag
	@echo 'create tag $(VERSION)'
	docker tag $(DOCKER_REPO)/$(API_NAME):latest $(DOCKER_REPO)/$(API_NAME):$(VERSION)

################################
####     SUPPORT COMMANDS   ####
################################

.PHONY: clean-docker
clean-docker: 
	@docker volume rm $(shell docker volume ls -qf dangling=true) 2>/dev/null ||:
	@docker rmi $(shell docker images -q -f dangling=true) 2>/dev/null ||:

.PHONY: clean-docker-volumes
clean-docker-volumes: 
	@docker $(shell docker rm -f `docker ps -a -q`) 2>/dev/null ||:
	@docker $(shell docker volume rm `docker volume ls -q`) 2>/dev/null ||:
