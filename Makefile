LUID := $(shell id -u)
LGID := $(shell id -g)
THIS_FILE := $(lastword $(MAKEFILE_LIST))
TS=.ts
CONTAINER-LIST = $(shell cat $(TS)/container-list 2>/dev/null)

##
## Services
## -------
##

.PHONY: pull
pull: ## 🛒 Pull docker images.
pull: docker-compose.yml $(TS)/pull
pull:
	@mkdir -p $(TS)
	@touch $(TS)/pull

$(TS)/pull: docker-compose.yml
	@$(MAKE) -s -f $(THIS_FILE) docker/pull || (echo '⛔ Fail target $@ ⛔'; exit 1;)
	@mkdir -p $(TS)
	@touch $@

.PHONY: setup
setup: ## 🏭 Setup containers.
setup: pull start $(TS)/setup
setup:
	@echo "⌛ Wait for service" && ./src/waituntil.sh && sleep 2
	@echo "📝 Update credentials" \
		&& docker run --rm --network=sonarqube_sonarnet \
			jbergknoff/postgresql-client \
				postgresql://sonar:sonar@sonarqube-db:5432/sonar -c "\x" -c "update users set reset_password=false where login = 'admin'" &>/dev/null;	
	@touch $(TS)/setup

$(TS)/setup:
	@sudo sysctl -w vm.max_map_count=262144 
	@sudo sysctl -w fs.file-max=65536
	@$(MAKE) -s -f $(THIS_FILE) docker/build || (echo '⛔ Fail target $@ ⛔'; exit 1;)
	@$(MAKE) -s -f $(THIS_FILE) start || (echo '⛔ Fail target $@ ⛔'; exit 1;)
	@mkdir -p $(TS)
	@touch $@

.PHONY: start
start: ## 🚀 Run dev environment.
start: DOCKER-ACTION=up -d --remove-orphans sonarqube sonarqube-db
start: docker

.PHONY: stop
stop: ## ⛔ Stop all docker containers.
stop: docker/stop

.PHONY: status
status: ## 📊 Show docker status.
status: docker/ps

logs: ## 🔬 Shows the logs of the development environment.
logs: DOCKER-ACTION=logs -f
logs: docker

.PHONY: config
config: ## 📄 Show config.
config: docker/config 

.PHONY: clean
clean: ## 🚿 Clean the build artifacts.
clean: docker/clean
	@rm -rf $(TS) \
			.env \
			logs/*.log

##
## Projects
## -------
##

.PHONY: cdev2
cdev2: ## 📳 Analize cdev2.
cdev2: setup
	@mkdir -p ${PWD}/logs
	@./src/cdev2.sh | tee ${PWD}/logs/cdev2.log

.PHONY: flash
flash: ## ⚡ Analize flash.
flash: setup
	@mkdir -p ${PWD}/logs
	@./src/flash.sh | tee ${PWD}/logs/flash.log

.PHONY: saas
saas: ## 🚚 Analize saas.
saas: setup
	@mkdir -p ${PWD}/logs
	@./src/saas.sh | tee ${PWD}/logs/saas.log

.PHONY: falcon
falcon: ## 🛸 Analize falcon.
falcon: setup
	@mkdir -p ${PWD}/logs
	@./src/falcon.sh | tee ${PWD}/logs/falcon.log

.PHONY: qm-events
qm-events: ## 💠 Analize qm-events.
qm-events: setup
	@mkdir -p ${PWD}/logs
	@./src/qm-events.sh | tee ${PWD}/logs/qm-events.log

.PHONY: stork
stork: ## 📅 Analize stork.
stork: setup
	@mkdir -p ${PWD}/logs
	@./src/stork.sh	| tee ${PWD}/logs/stork.log

.PHONY: t_and_t
t_and_t: ## 🎁 Analize track & trace.
t_and_t: setup
	@mkdir -p ${PWD}/logs
	@./src/t_and_t.sh | tee ${PWD}/logs/t_and_t.log

.PHONY: fleet
fleet: ## 🔌 Analize fleet-listener.
fleet: setup
	@mkdir -p ${PWD}/logs
	@./src/fleet.sh | tee ${PWD}/logs/fleet.log 

##
## Utils
## -------
##

##  
## 🌐 Browser.
## 
open-browser:
	@URL="http://localhost:9999"; xdg-open $${URL} || sensible-browser $${URL} || x-www-browser $${URL} || gnome-open $${URL}

##  
## 🐳 Docker targets.
## 

.PHONY: docker/pull
docker/pull: DOCKER-ACTION:=pull ${CONTAINER-LIST} ## 🐳 Get all docker images.
docker/pull: docker

.PHONY: docker/build
docker/build: DOCKER-ACTION:=build --parallel ${CONTAINER-LIST} ## 🐳 Build all docker images.
docker/build: docker

.PHONY: docker/down
docker/down: DOCKER-ACTION=down ## 🐳 Down docker containers process.
docker/down: docker

.PHONY: docker/stop
docker/stop: DOCKER-ACTION=stop ## 🐳 Stop docker containers process.
docker/stop: docker

.PHONY: docker/clean
docker/clean: DOCKER-ACTION=down -v --remove-orphans ## 🐳 Remove all docker containers, networks and volumen.
docker/clean: docker

.PHONY: docker/ps
docker/ps: DOCKER-ACTION=ps ## 🐳 Show docker process.
docker/ps: docker

.PHONY: docker/config
docker/config: ## 🐳 Show docker-compose config.
	@export LUID=${LUID} LGID=${LGID}; \
	 docker-compose config

.PHONY: docker
docker: ## 🐳 Run docker command.
docker: $(TS)/container-list
	@if [ "x_${DOCKER-ACTION}_x" = "x__x" ] || [ "x_${CONTAINER-LIST}_x" = "x__x" ]; then \
		exit 0; \
	else \
		export LUID=${LUID} LGID=${LGID} DOCKER_BUILDKIT=1 PROJECT_SOURCE=${PWD}; \
	 ( ((echo ${DOCKER-ACTION} | grep -q -v -E '(down|build|pull|ps|stop|logs|exec)') \
	 	&& docker-compose up \
	 		--remove-orphans \
	 		--no-recreate \
	 		--no-start ${CONTAINER-LIST}) || true ) \
	&& docker-compose ${DOCKER-ACTION}; \
	fi

##
## Help
## -------
##

.DEFAULT_GOAL := help
.PHONY: help
help: ## 🆘 Show make targets.
	@grep -E '(^([a-zA-Z_-]|/|-)+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

$(TS)/container-list: docker-compose.yml
	@mkdir -p $(TS)
	@docker run --rm -i -v ${PWD}:/workdir mikefarah/yq eval '.services.* | path | .[-1]' -C -e docker-compose.yml | sed ':a;$!N;s/\n/ /;ta;s/,,/\n\n/g'>$(TS)/container-list
	@touch $(TS)/container-list
