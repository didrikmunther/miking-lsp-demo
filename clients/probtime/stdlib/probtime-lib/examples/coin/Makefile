run: cf
	python3 run.py

cf: coin.rpl
	rtppl $< --debug-parse

clean:
	rm -rf cf cf.collect cf-in1 bias system.json __pycache__
