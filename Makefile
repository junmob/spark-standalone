build:
	docker compose build

build-nc:
	docker compose build --no-cache

build-progress:
	docker compose build --no-cache --progress=plain

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

# run-scaled:
# 	make down && docker compose up --scale spark-worker=3

run-generated:
	make down && sh ./generate-docker-compose.sh 3 && docker compose -f docker-compose.generated.yml up

# --------------------------------------------------------------------

submit:
	docker exec spark-master spark-submit --master spark://spark-master:7077 --deploy-mode client /opt/spark/apps/apps/$(app)

submit-py-pi:
	docker exec spark-master spark-submit --master spark://spark-master:7077 /opt/spark/examples/src/main/python/pi.py

rm-results:
	rm -r data/results/*