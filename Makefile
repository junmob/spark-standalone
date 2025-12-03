build:
	COMPOSE_BAKE=true docker compose build

build-nc:
	COMPOSE_BAKE=true docker compose build --no-cache

build-progress:
	COMPOSE_BAKE=true docker compose --progress=plain build --no-cache

# --------------------------------------------------------------------

clean:
	docker compose down --rmi="all" --volumes

down:
	docker compose down --volumes --remove-orphans

stop:
	docker compose stop

# --------------------------------------------------------------------

run:
	make down && docker compose up

run-d:
	make down && docker compose up -d

run-scaled:
	make down && docker compose up --scale spark-worker=3 -d

run-generated:
	make down && bash ./generate-docker-compose.sh 3 && docker compose -f docker-compose.generated.yml up -d

# --------------------------------------------------------------------

logs:
	docker compose -f docker-compose.generated.yml logs -f

logs-master:
	docker logs -f spark-master

logs-jupyter:
	docker logs -f spark-jupyter

# --------------------------------------------------------------------

submit:
	docker exec spark-master spark-submit --master spark://spark-master:7077 --deploy-mode client /opt/spark/apps/$(app)

submit-py-pi:
	docker exec spark-master spark-submit --master spark://spark-master:7077 /opt/spark/examples/src/main/python/pi.py

rm-results:
	rm -r data/results/*