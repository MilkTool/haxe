//test strings
var srcStr = 'hello, world';
var d = new haxe.Http('http://localhost:20200/echoServer.n');
d.onData = echoStr -> {
	if(echoStr != srcStr) {
		throw 'String data from Http request is corrupted: $echoStr';
	}
}
d.onError = e -> throw 'Failed Http request with string data: $e';
d.setPostData(srcStr);
d.request();

//test binary
var srcData = haxe.io.Bytes.alloc(100);
for(i in 0...srcData.length) {
	srcData.set(i, Std.random(256));
}
var d = new haxe.Http('http://localhost:20200/echoServer.n');
d.onBytes = echoData -> {
	for(i in 0...echoData.length) {
		if(srcData.get(i) != echoData.get(i)) {
			throw 'Binary data from Http request is corrupted';
		}
	}
}
d.onError = e -> throw 'Failed Http request with binary data: $e';
d.setPostBytes(srcData);
d.request();

1 == 1;