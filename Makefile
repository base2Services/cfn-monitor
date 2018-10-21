all:

build:
	docker build -t cloudwatch-monitoring:latest .

run:
	docker run -ti --rm cloudwatch-monitoring:latest