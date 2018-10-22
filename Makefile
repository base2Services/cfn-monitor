all:

build:
	docker build -t cloudwatch-monitoring:latest .

test:
	docker run -ti --rm cloudwatch-monitoring:latest ps -ef
	docker run -ti --rm cloudwatch-monitoring:latest echo multiple arguments | grep "multiple arguments" > /dev/null || { echo "Multiple arguments ignored" && false; }
	docker run -ti --rm cloudwatch-monitoring:latest ls | grep "templates" > /dev/null || { echo "Files not copied to working dir" && false; }
	docker run -ti --rm cloudwatch-monitoring:latest env | grep "GEM_PATH" > /dev/null || { echo "No gempath, not loading login shell" && false; }
	docker run -ti --rm cloudwatch-monitoring:latest rake --tasks
	docker run -ti --rm cloudwatch-monitoring:latest rake cfn:test
	echo | docker run -ti --rm cloudwatch-monitoring:latest

run:
	docker run -ti --rm cloudwatch-monitoring:latest