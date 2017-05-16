class Output

  constructor: (optionsArg) ->

    options = optionsArg ? {}

    @writer  = options.writer
    @target  = options.target
    @size    = options.size ? 1024
    @index   = 0
    # gets an underscore cuz `@buffer` is a function
    @buf = Buffer.allocUnsafe @size

    # remember most recent specifier byte ("marker")
    # so we can collapse some pairs into one.
    # such as:
    #   1. BEGIN_OBJECT + OBJECT = BEGIN_OBJECT
    #   2. SUB_TERMINATOR + TERMINATOR = TERMINATOR
    @_conditionalMarker = @byte
    # placeholders
    @previousMarker = null
    @_testMarker    = null

    # make send() and complete() according to writing or buffer list
    if @writer?
      @complete = @_flush
      @send     = @_stream
      @buffers  = null

    else
      @complete = @_gather
      @send     = @_append
      @buffers  = []


  # ensure we have this many open bytes in our buffer.
  # NOTE: only do this after setting a marker() so there's no
  # conditional marker evaluation waiting to run.
  # it's possible to retain the last byte just in case, but,
  # why do that if we can avoid it.
  prepare: (bytes) ->

    if bytes < (@size - @index)

      # cap the buffer (without last byte) and send it
      @buf = @buf.slice 0, @index
      @send()

      # create new buffer with *at least* enough space and reset index
      @buf = @allocate Math.max bytes, @size
      @index = 0

    return

  # NOTE: we're using the unsafe version because we don't care what
  # it's pre-filled with because we are going to write into it
  # and either use the whole thing, or, know where we left off,
  # and copy up to that out to another buffer of the exact size
  # we need. so, we'll never use a section we didn't write into.
  allocate:
    # allocUnsafe isn't available in Node 4
    if Buffer.allocUnsafe? then (size) -> Buffer.allocUnsafe size
    else (size) -> new Buffer size

  # when we have a write function then this is how we use it.
  # NOTE: this is assigned to `@send` when we have a `@writer`
  _stream: -> @writer.call @target, @buf


  # when we are doing sync work then this is how we handle buffers.
  # NOTE: this is assigned to `@send` when we *dont* have a `@writer`
  _append: ->
    @buffers ?= []
    @buffers[@buffers.length] = @buf

  _finish: -> # if there is a lingering marker then use it now.
    if @_conditionalMarker is @_unlessNext
      @_conditionalMarker = @byte
      @byte @previousMarker

  # combines all stored buffers and the valueable part of our current buffer.
  # NOTE: used as `@complete()`, assigned when there's no `@writer`
  _gather: ->

    @_finish()

    buffers = @buffers ? []

    # multiply the size we used for each times the number of buffers we stored.
    # add in the number we have in our last buffer (@index).
    length = (buffers.length * @size) + @index

    # add our last buffer in there
    buffers[buffers.length] = @buf

    # combine them all with our `length` to avoid the unused portion of the
    # last buffer.
    buffer: Buffer.concat buffers, length


  # sends the part of `@buf` which matters on to the stream
  # NOTE: used as `@complete()`, assigned when there is a `@writer`
  _flush: ->

    @_finish()

    # get only the part we want, leave out the remaining unused portion.
    if @index < @size then @buf = @buf.slice 0, @index

    # else, the buffer is full, so, use it as-is.

    @send()

    success:true

  #
  # Marker conditional stuffs to collapse redundant specifiers.
  #

  # same as @byte() when @_conditionalMarker is assigned to it,
  # otherwise it's assigned to _unlessNext which handles a condition.
  marker: (byte) ->
    @_conditionalMarker byte
    @previousMarker = byte
    return

  # this avoids sending the marker if the previous one makes it unnecessary.
  # collapse: BEGIN_OBJECT   + OBJECT = BEGIN_OBJECT
  # use both: SUB_TERMINATOR + OBJECT = SUB_TERMINATOR + OBJECT
  markerUnlessPreviousWas: (byte, previous) ->
    if @previousMarker isnt previous then @marker byte

  # collapse: SUB_TERMINATOR + TERMINATOR = TERMINATOR
  # use both: SUB_TERMINATOR + VARINT     = SUB_TERMINATOR + VARINT
  markerUnlessNextIs: (byte, next) ->
    @previousMarker = byte
    @_testMarker     = next
    @_conditionalMarker = @_unlessNext

  # this avoids sending one when the next one makes it unnecessary.
  # it's assigned to @_conditionalMarker to intercept the next marker.
  _unlessNext: (nextByte) ->
    # if the next byte to call marker() is the one we're watching for
    # then *only* send the new byte
    if @previousMarker is null or @_testMarker is nextByte then @byte nextByte

    # otherwise, send them both
    else @byte2 @previousMarker, nextByte

    # then return to handling things normally
    @_conditionalMarker = @byte
    return


  # append a single byte value and increment, possibly getting a new buffer.
  byte: (byte) ->

    @buf[@index] = byte
    @increment 1
    return


  byte2: (byte1, byte2) ->

    if @index + 1 < @size
      @buf[@index] = byte1
      @buf[@index + 1] = byte2
      @increment 2

    else
      @byte byte1
      @byte byte2

    return


  byte3: (byte1, byte2, byte3) ->

    if @index + 2 < @size
      @buf[@index] = byte1
      @buf[@index + 1] = byte2
      @buf[@index + 2] = byte3
      @increment 3

    else
      @byte byte1
      @byte byte2
      @byte byte3

    return


  byte4: (b1, b2, b3, b4) ->

    if @index + 3 < @size
      @buf[@index] = b1
      @buf[@index + 1] = b2
      @buf[@index + 2] = b3
      @buf[@index + 3] = b3
      @increment 4

    else
      @byte b1
      @byte b2
      @byte b3
      @byte b4

    return


  float4: (value) ->

    if 4 <= (@size - @index)
      @buf.writeFloatBE value, @index, true
      @increment 4

    else
      buffer = @allocate 4
      buffer.writeFloatBE value, 0, true
      @buffer buffer

    return

  float8: (value) ->

    if 8 <= (@size - @index)
      @buf.writeDoubleBE value, @index, true
      @increment 8

    else
      buffer = @allocate 8
      buffer.writeDoubleBE value, 0, true
      @buffer buffer

    return

  int: (value, bytes) ->

    # use current buffer if there's enough room, or allocate a new buffer.

    if bytes <= (@size - @index)
      @buf.writeUIntBE value, @index, bytes, true
      @increment bytes

    else
      buffer = @allocate bytes
      buffer.writeUIntBE value, 0, bytes, true
      @buffer buffer

    return


  buffer: (buffer) ->

    diff = @size - @index

    if buffer.length <= diff

      buffer.copy @buf, @index, 0, buffer.length
      @increment buffer.length

    else if buffer.length < @size

      buffer.copy @buf, @index, 0, diff
      @send()
      @renew()
      buffer.copy @buf, 0, diff, buffer.length

    else

      # fill the current buffer
      buffer.copy @buf, @index, 0, diff
      @send()
      # set the partial (slice) buffer in place to send() it
      @buf = buffer.slice diff, buffer.length
      @send()
      @renew()

    return


  string: (string, byteLength) ->

    # if we have that many bytes left in our buffer then use them
    if @index + byteLength < @buf.length
      # console.log 'output.string',@index, byteLength, @buf.length
      @buf.write string, @index, byteLength, 'utf8'
      @increment byteLength


    else if byteLength > @size

      # cap the current buffer and send it
      @buf = @buf.slice 0, @index
      @send()

      # write our string into a buffer to send
      @buf = @allocate byteLength
      @buf.write string, 0, byteLength, 'utf8'
      @send()

      # make a new buffer
      @renew()

    else # fill remainder of buffer, increment it, put remainder in new buffer

      # amount of space we have in the current buffer
      diff = @size - @index

      # put that much into the buffer to fill it
      @buf.write string, 0, diff, 'utf8'

      # increment by that much so it'll send() and make a new buffer
      @send()
      @renew()

      # write the remainder into the new buffer
      @index = @buf.write string, diff, byteLength - diff, 'utf8'

    return


  renew: ->
    @index = 0
    @buf = @allocate @size


  increment: (amount) ->

    @previousMarker = null

    index = @index + amount

    if index >= @buf.length

      @send()
      @renew()

    else
      @index = index

    return


module.exports = (options) -> new Output options
module.exports.Output = Output
