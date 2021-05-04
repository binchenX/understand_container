run:
	docker run --rm -it -p 8000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material

release-s3:
	zip -r uc.zip . -x '*.git*'
	aws s3 cp uc.zip s3://devicu-devops/uc/uc.zip
	rm uc.zip
