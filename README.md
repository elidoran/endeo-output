# @endeo/output
[![Build Status](https://travis-ci.org/elidoran/endeo-output.svg?branch=master)](https://travis-ci.org/elidoran/endeo-output)
[![Dependency Status](https://gemnasium.com/elidoran/endeo-output.png)](https://gemnasium.com/elidoran/endeo-output)
[![npm version](https://badge.fury.io/js/%40endeo%2Foutput.svg)](http://badge.fury.io/js/%40endeo%2Foutput)
[![Coverage Status](https://coveralls.io/repos/github/elidoran/endeo-output/badge.svg?branch=master)](https://coveralls.io/github/elidoran/endeo-output?branch=master)

Send bytes to buffer list or stream.

See packages:

1. [endeo](https://www.npmjs.com/package/endeo)
2. [enbyte](https://www.npmjs.com/package/enbyte)


## Install

```sh
npm install --save @endeo/output
```


## Usage


```javascript
// get the builder
var Output = require('@endeo/output')

// build one for synchronous operation
var output = new Output()

// or, build one for async operation
var stream = getSomeStream()
// target a Writable stream
var output = new Output(stream.write, stream)
// target a Transform stream
var output = new Output(transform.push, transform)

// optionally have output prepare to accept a
// certain number of bytes.
output.prepare(8)

// either way, it is used the same.
// specify a single byte value.
// this is appended to an internal buffer.
// when the buffer is full:
//   1. the sync version stores it in an array of buffers
//   2. the async version sends it to the stream
output.byte(0xAB)

// send more than one byte at once:
output.byte2(0x01, 0x02)
output.byte3(0x01, 0x02, 0x03)
output.byte4(0x01, 0x02, 0x03, 0x04)

// send specific number sizes:
//   'short' is 2 bytes
output.short(12345)
// int is for 1 to 6 bytes ints.
output.int(1234567890, 4)

// and floats (4 bytes, 8 bytes):
output.float4(1.25)
output.float8(12345.123456789)

// and a string:
// Note: UTF8 encoding is used
output.string('some string')

// finally, a Buffer
output.buffer(someBuffer)


// when all bytes have been provided get the result:
//
// 1. sync operation provides a single Buffer with all content
buffer = output.complete()
//
// 2. async operation ensures what's left is sent forward.
//    (basically, flush)
result = output.complete()
//
// the result for async is something to show success:
result = {
  success: true
}
```


# [MIT License](LICENSE)
