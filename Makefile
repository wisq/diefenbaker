all:

bundle:
	@test "$$USER" = "diefenbaker" || (echo "This task is meant to be run on production only." && exit 1)
	bundle check || bundle install --path .bundle/gems --deployment
