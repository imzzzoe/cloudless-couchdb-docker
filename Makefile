.PHONY : clean setup run-tests

creds := jan:password
couchdb := http://$(creds)@127.0.0.1:5984
db := test-database
dir := $(shell pwd)/test
curl_post := @curl -s -X POST -H "Content-Type: application/json" -u $(creds)
curl_put := @curl -s -X PUT -H "Content-Type: application/json" -u $(creds)
hadolint := docker run --rm -i hadolint/hadolint hadolint
release := couchdb-test-cluster

helm-deploy:
	@echo "Building images"
	eval $(minikube docker-env)
	$(MAKE) docker-build image_name=clouseau-test docker_file=./clouseau/Dockerfile
	$(MAKE) docker-build image_name=couchdb-test docker_file=./couchdb/Dockerfile
	@echo "Deploying to Minikube"
	helm install --name $(release) ./.helm/cloudless-couchdb
	@echo "Finish cluster setup by running: make cluster"

cluster:
	for number in 0 1 2 ; do \
		kubectl exec -it $(release)-couchdb-$$number -c couchdb -- \
			curl -s \
			$(couchdb)/_cluster_setup \
			-X POST \
			-H "Content-Type: application/json" \
			-d '{"action": "finish_cluster"}' \
			-u "$(creds)" ; \
	done
	kubectl expose service $(release)-svc-couchdb --type=LoadBalancer --name=couchdb-public
	minikube service couchdb-public --url

# in the end this will do the following:
# 1. confirm configuration we set (so it's applied)
# 2. confirm membership (count all_nodes vs. cluster_nodes in /_membership)
cluster-status:
	for number in 0 1 2 ; do \
		kubectl exec -it $(release)-couchdb-$$number -c couchdb -- \
			curl -s $(couchdb)/_node/_local/_config/httpd/bind_address \
			&& curl -s $(couchdb)/_node/_local/_config/chttpd/bind_address ; \
	done

helm-lint:
	helm lint ./.helm/cloudless-couchdb

helm-undeploy:
	@echo "Removing release"
	helm delete --purge $(release)
	kubectl delete service/couchdb-public

helm-upgrade:
	helm upgrade $(release) ./.helm/cloudless-couchdb

clean:
	$(eval endpoint := $(shell minikube service couchdb-public --url))
	@echo "Deleting $(db)"
	curl -X DELETE -u $(creds) $(endpoint)/$(db)

setup:
	$(eval endpoint := $(shell minikube service couchdb-public --url))
	@echo "Creating database(s) on all nodes of cluster $(endpoint)"
	$(curl_put) $(endpoint)/$(db)
	@echo "Populating '$(db)' with test data/fixtures"
	$(curl_post) -d @$(dir)/doc1.json $(endpoint)/$(db)
	$(curl_post) -d @$(dir)/doc2.json $(endpoint)/$(db)
	$(curl_post) -d @$(dir)/doc3.json $(endpoint)/$(db)
	$(curl_post) -d @$(dir)/doc4.json $(endpoint)/$(db)
	@echo "Creating index (Mango)"
	$(curl_post) -d @$(dir)/test-index1.txt $(endpoint)/$(db)/_index

run-tests:
	$(eval endpoint := $(shell minikube service couchdb-public --url))


docker-lint:
	$(hadolint) --ignore DL3008 --ignore DL3015 - < ./couchdb/Dockerfile
	$(hadolint) --ignore DL3008 --ignore DL3015 - < ./clouseau/Dockerfile
	$(hadolint) - < ./maven-mirror/Dockerfile-mirror
	$(hadolint) - < ./maven-mirror/Dockerfile-push

docker-build:
	docker build -t $(image_name) -f $(docker_file) .

test: clean setup run-tests
