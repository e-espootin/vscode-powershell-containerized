.PHONY: run cleanup

run:
	docker-compose up -d

cleanup:
	docker-compose down --remove-orphans

logs:
	docker-compose logs -f

build:
	docker-compose build

restart:
	docker-compose restart