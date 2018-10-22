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
	echo ls | docker run -i --rm cloudwatch-monitoring:latest | grep "templates" > /dev/null || { echo "Stdin mode isn't working" && false; }

run:
	docker run -ti --rm cloudwatch-monitoring:latest