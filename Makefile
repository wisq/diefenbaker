all:

bundle:
	bundle check || bundle install --path .bundle/gems --deployment
