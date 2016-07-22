
default:	build

clean:
	rm -rf Makefile objs

build:
	$(MAKE) -f objs/Makefile
	$(MAKE) -f objs/Makefile manpage

install:
	$(MAKE) -f objs/Makefile install

upgrade:
	/Users/aschlosser/Dev/api-gateway/nginx/build/sbin/nginx -t

	kill -USR2 `cat /Users/aschlosser/Dev/api-gateway/nginx/build/logs/nginx.pid`
	sleep 1
	test -f /Users/aschlosser/Dev/api-gateway/nginx/build/logs/nginx.pid.oldbin

	kill -QUIT `cat /Users/aschlosser/Dev/api-gateway/nginx/build/logs/nginx.pid.oldbin`
