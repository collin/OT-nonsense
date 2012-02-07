
# Binary operation identifier constants are used to decode/encode operations
# for wire transmission.
INSERT = 0x01
DELETE = 0x02
RETAIN = 0x03

BEGIN_ANNOTATION = 0x04
DELETE_BEGIN_ANNOTATION = 0x05
END_ANNOTATION = 0x06
DELETE_END_ANNOTATION = 0x06

OPEN_ENTITY = 0x7
DELETE_OPEN_ENTITY = 0x08
CLOSE_ENTITY = 0x09
DELETE_CLOSE_ENTITY = 0x0A


# `TODO: Fold in a more reusable StateMachine implementation to the ClientDocumentController
# take from alpha-simprini-engine`
READYSTATE = "READYSTATE"
INFLIGHTSTATE = "INFLIGHTSTATE"

# # Operational Transformation
# <iframe src="overview.html" width="100%" height="320" style="border: none;"></iframe>
# Operation Transformation is a means for real-time collaborative document authoring via a network.
# 
# A document is considered as a series of operations necessary to create the document. Edits to the document are committed as the necessary operations to bring the document from one state to another.
# 
# This allows for optimistic, lock-free, concurrency with multiple authors while retaining zero-latency for application of local operations.
# 
# When operations would conflict a transformation is applied to the operations.
# 
# `transform(a, b) = (a', b') where b' ∘ a ≡ a' ∘ b`
# 
# The transform function transforms two operations, a and b, into the operations a-prime, and b-prime. Either of the operation pairs, [b', a] and [a', b] may be applied to a document and will result in the same final document.
# 

# ## Some little utility functions. 
# `uniq` generates a probably unique identifier.
# large random numbers are base32 encoded and combined with the current time base32 encoded
uniq = -> 
  (Math.floor Math.random() * 100000000000000000).toString(32) + "-" + (Math.floor Math.random() * 100000000000000000).toString(32) + "-" + (new Date).getTime().toString(32)

# ## MemoryStore
# A basic implementation for document storage. It exposes two methods.
# `get(documentOrdocumentId)` and `add(document)`. To implement custom storage study this
# dead simple object to fully understand how the methods are expected to behave.
class MemoryStore
  constructor: ->
    @documents = {}
  
  # `add(document)` adds a document to the storage. Documents have an id property
  # which should be used for primay indexing and lookup.
  add: (document) -> @documents[document.id] = document
  
  # `get(dacumentId)` retreives a document from storage.
  get: (documentId) -> @documents[documentId]

# class RedisStore
#   redis = require("redis")
#   redis.auth process.env.OT_REDIS_PASSWORD
#   
#   DOCUMENT_BUFFERS = 0x00
#   OPERATION_BUFFERS = 0x01
#   
#   constructor: ->
#     @redis = redis.createClient()
#   
#   add: (document) ->
#     documentKey = @documentKey(document)
#     buffersKey = @buffersKey(document)
# 
#     @redis.rpush documentKey, JSON.stringify(document.documentBufffer.encode())
#     @redis.rpush buffersKey(document), JSON.stringify(document.last().encode())
#   
#   get: (documentId) ->
#     documentKey = @documentKey(document)
#     buffersKey = @buffersKey(document)
#     
#     decodedDocument = DocumentBuffer.decode JSON.parse @redis.lrange documentKey, -1, 1
#     decodedBuffer = OperationBuffer.decode JSON.parse @redis.lrange buffersKey, -1, 1
#     
#     new Document documentId, decodedDocument, decodedBuffer
#     
#   exists: (document) ->
#     redis.exists @documentKey(document)
#   
#   documentKey: (document) ->
#     "#{DOCUMENT_BUFFERS}#{document.id}"
#   
#   buffersKey: (document) ->
#     "#{OPERATION_BUFFERS}#{document.id}"
  
## Client
# Calls the shots on the client. A browser, or other client session is expected
# only to need one instance of Client at a time. _(I will probably be surprised,
# so this isn't a singleton.)_ The client serves as the glue between the network,
# document storage, and the user interface.
class Client

  # `TODO: Allow for transports other than nowjs`
  #
  # ## `new Client(@now, backingStore=MemoryStore)`
  # The client is initialized with a now.js ["_magic pocket_"](http://nowjs.com/guide#magicpockets)
  # and a backing document store. The `backingStore` defaults to MemoryStore.
  #
  # The client registers a `receiveOperation` function for the server to call
  # with corresponding now.js ["_magic pocket_"](http://nowjs.com/guide#magicpockets).
  #
  # It's worth reading those links about the ["_magic pocket_"](http://nowjs.com/guide#magicpockets).
  # It's dead simple and will help you understand what's going on in the client.
  #
  # Any document specific processing is handled by a `ClientDocumentController`.
  # Each document tracked by the client has it's own `ClientDocumentController`.
  constructor: (@now, @store = new MemoryStore) ->
    @now.receiveOperation = => @receiveOperation.apply(this, arguments)
    @controllers = {}
  
  # `FIXME: figure out auth(entication/authorization) hooks for document subscription.`
  #
  # ## `addDocument(document)` 
  # adds a document to the document store and subscribes
  # the client to updates from the server. Clients will only receive operations
  # for documents they are subscribed to. This is done using a
  # [now.js group](http://nowjs.com/jsdoc/symbols/Group.html).
  addDocument: (document) ->
    @now.subscribeToDocument(document.id)
    @store.add(document)
  
  # ## `receiveOperation(documentId, encodedOperationBuffer)` 
  # recieves an operation
  # directly from the server. The operation is decoded into an `OperationBuffer`
  # object. The specific `ClientDocumentController` object for the document
  # is called upon to process the document.
  receiveOperation: (documentId, encodedOperationBuffer) ->
    operationBuffer = OperationBuffer.decode(encodedOperationBuffer)
    controller =  @controller(documentId)
    controller.receiveRemoteOperation(operationBuffer)
  
  # ## `applyLocalOperation(document, fn)` 
  # creates on `OperationBuffer` from a function
  # and delegates to a controller to apply the operation.
  applyLocalOperation: (document, fn) ->
    operationBuffer = (new OperationBuffer).exec(fn)
    @controller(document).applyLocalOperation(operationBuffer)
  
  # ## `controller(documentOrDocumentId)` 
  # retreives or creates a `ClientDocumentController` 
  # for the corresponding document.
  controller: (documentOrDocumentId) ->
    if documentOrDocumentId instanceof Document
      documentId = documentOrDocumentId.id
    else
      documentId = documentOrDocumentId
    
    if @controllers[documentId] is undefined
      document = @store.get(documentId)
      controller = new ClientDocumentController(@now, document)
      @controllers[documentId] = controller
    else
      controller = @controllers[documentId]
    
    controller

## ClientDocumentController
# Where the client side Operational Transformation control structure lives.

class ClientDocumentController 
  
  constructor: (@now, @document) ->
    @state = READYSTATE
    @buffer = new OperationBuffer
    @inflightOperation = null
    
  ready: -> @state is READYSTATE
  inflight: -> @state is INFLIGHTSTATE
  
  receiveRemoteOperation: (operationBuffer) ->
    if @document.ack(operationBuffer.id)
      # HEY THIS IS OUR OPERATION, WE WIN!
      unless @inflight()
        throw new Error [
          "Received acknowledgment of operation but wasn't inflight()"
        ]
      
      # change state before delivery, state may flip back
      @state = READYSTATE
      
      # OH BALLS
      # SEND THE BUFFER :! THE BUFFER IS DEAD LONG LIVE THE BUFFER
      @deliverOperation(@buffer)
      @buffer = new OperationBuffer
    else
      if @inflightOperation is null
        # Nothing inflight, should apply cleanly
        # Only compose the operation buffer when inflight.
        # Otherwise we'll end up with a big buffer of operation composed
        # against nothing of our own.
        @composeOperationBuffer(operationBuffer) if @inflight()
        @document.compose(operationBuffer, remote: true)
      else
        # We're inflight, need to compose and transform
        operationBufferPrime = new OperationBufferTransformer(operationBuffer, @inflightOperation).aPrime()
        @composeOperationBuffer(operationBufferPrime)
        @document.compose(operationBufferPrime, remote: true)
            
  applyLocalOperation: (operationBuffer) ->
    @document.compose operationBuffer
    if @inflight()
      @composeOperationBuffer(operationBuffer)
    else
      operationBuffer.id = @document.currentBuffer.id
      operationBuffer.parentId = @document.currentBuffer.parentId
      @deliverOperation(operationBuffer)
  
  deliverOperation: (operationBuffer) ->
    if operationBuffer.operations.length
      @inflightOperation = operationBuffer
      @now.deliverOperation(@document.id, operationBuffer.encode())
      @state = INFLIGHTSTATE
    else
      @inflightOperation = null

  composeOperationBuffer: (operationBuffer) ->
    @buffer = new OperationBufferComposer(@buffer, operationBuffer).compose()

class Server

  constructor: (@nowjs, @store = new MemoryStore) ->
    @controllers = {}

    everyone = @nowjs.getGroup("everyone")
    everyone.now.deliverOperation = @receiveOperation    
    everyone.now.subscribeToDocument = @subscribeToDocument

  subscribeToDocument: (documentId) =>
    @controller(documentId).addUser(@user.clientId)
    
  receiveOperation: (documentId, operationBuffer) =>
    document = @store.get(documentId)
    controller = @controller(documentId)
    controller.receiveOperation(OperationBuffer.decode(operationBuffer))
  
  controller: (documentId) ->
    document = @store.get(documentId) or @store.add(new Document(documentId))
    group = @nowjs.getGroup(documentId)
    @controllers[documentId] ?= new ServerDocumentController(group, document)
    
class ServerDocumentController
  events:
    "update @document": "write_document"
  
  constructor: (@group, @document, @store) ->
    @document.on "update", @write_document
    
  addUser: (userId) ->
    @group.addUser(userId)
    # @broadcast @document.currentBuffer
    
  write_document: =>
    @store.add(@document)

  receiveOperation: (operationBuffer) ->
    # FIXME: `or operationBuffer.parentId is undefined or !@document.ack(operationBuffer.parentId)` should indicate an error. Come up with a better way to "handshake" documents so this doesn't happen
    if operationBuffer.parentId is @document.currentBuffer.id or operationBuffer.parentId is undefined or !@document.ack(operationBuffer.parentId)
      @document.compose(operationBuffer)
      @broadcast(@document.currentBuffer)
    else
      composedOperationBuffer = @document.composeBufferFromState(operationBuffer.parent)
      transformedOperationBuffer = @transform(operationBuffer, composedOperationBuffer)
      @document.compose(transformedOperationBuffer)
      @broadcast(transformedOperationBuffer)
  
  transform: (operationBuffer, composedOperationBuffer) ->
    new OperationBufferTransformer(operationBuffer, composedOperationBuffer).aPrime()
  
  broadcast: (operationBuffer) ->
    # FIXME: this is sort of a bad way to ensure this sticks around.
    # Should be done in the cloning of the buffer
    operationBuffer.id = @document.currentBuffer.id
    operationBuffer.parent = @document.currentBuffer.parent
    
    @group.now.receiveOperation @document.id, operationBuffer.encode()

class Document
  
  constructor: (@id=uniq(), @documentBuffer = new DocumentBuffer, operationBuffer) ->
    @buffers = []
    @buffersById = {}
    @pushbuffer(operationBuffer)
    # `@documentBuffer` is the fully composed document.
    # The DocumentBuffer is an OperationBuffer that uses an identity function
    # as it's clone method. In this way the same operation objects are preserved
    # between operations. This makes tracking changes easier/possible/sane
    # for client applications.
  
  emit: (event) ->
    receiver[0].call(receiver[1], this) for receiver in @receivers?[event] or []
  
  last: -> @buffers[@buffers.length - 1]
  
  on: (event, fn, context) ->
    @receivers ?= {}
    @receivers[event] ?= []
    @receivers[event].push [fn, context]

  ack: (bufferId) -> @buffersById[bufferId]?

  pushbuffer: (operationBuffer = new OperationBuffer) ->
    operationBuffer.parentId = @currentBuffer?.id
    @buffersById[operationBuffer.id] = operationBuffer
    @buffers.push @currentBuffer = operationBuffer
    @currentBuffer
    
  # Compose the operationBuffer into the @documentBuffer and push the operationBuffer
  # into the @buffers stack. Emits an `update` event.
  #
  # `FIXME?: emit 'compose' event`
  compose: (operationBuffer, options={}) ->
    # Only emit composition events on remote updates
    if options.remote
      composer = new OperationBufferComposer @documentBuffer, operationBuffer, this
    else
      composer = new OperationBufferComposer @documentBuffer, operationBuffer
      
    @documentBuffer = composer.compose()
    @pushbuffer(operationBuffer)
    
    if options.remote
      @emit("remoteupdate")
    else
      @emit("localupdate")
      
    @emit("update")
  
  composeBufferFromState: (bufferId) ->
    composedBuffer = targetBuffer = @buffersById[buffersById]
    buffers = []
    while buffers[buffers.length] isnt targetBuffer
      buffers.unshift @buffersById[buffers[buffers.length].parentId]
    
    for buffer in buffers.reverse()
      composedBuffer = new OperationBufferComposer(composedBuffer, buffer).compose()
    
    return targetBuffer 
  
  toString: -> @documentBuffer.toString()

class Operation

  constructor: (@operationBuffer) ->

  for unimplementedMethod in ["length", "clone", "merge"]
    @::[unimplementedMethod] = ->
      throw new Error("Unimplemented method #{unimplementedMethod} for class #{constructor.name}")

  empty: -> @length() is 0

class CharacterOperation extends Operation

  constructor: (@characters) ->

  length: -> @characters.length

  clone: -> new @constructor @characters

  merge: (operation) ->
    @characters += operation.characters

  slice_at: (characters, position) ->
    characters_to_splice = @characters.slice(position, position + characters.length)
    unless characters_to_splice is characters_to_splice
      throw new Error "IllegalCharacterDeletion tried to delete '#{characters}' 
      from '#{@characters}' at position #{position}. 
      Actual characters were '#{characters_to_splice}'"
    split = @characters.split ""
    split.splice position, characters_to_splice.length
    @characters = split.join ""

  insert: (characters, position) ->
    split = @characters.split("")
    split.splice position, 0, characters
    @characters = split.join ""

class InsertCharacters extends CharacterOperation
  @constant = INSERT

  encode: -> [INSERT, @characters]

class DeleteCharacters extends CharacterOperation
  @constant = DELETE

  encode: ->  [DELETE, @characters]

class Retain extends Operation
  @constant = RETAIN

  constructor: (@characters) ->

  length: -> @characters.length

  clone: -> new Retain @characters

  merge: (operation) ->
    if @characters instanceof String
      @characters += operation.characters
    else
      @characters.length += operation.length()

    new Error("Unimplemented method length for class #{constructor.name}")

  # Sometimes we want to insert characters right in the middle of a Retain.
  # So we splice the characters directly into the retain. It's pretty sweet.
  splice_at: (characters, position) ->
    split = @characters.split("")
    split.splice.apply split, [position, 0].concat(characters.split(""))
    @characters = split.join("")

  encode: -> [RETAIN, @characters]

# # Tag Operations
class TagOperation extends Operation

  constructor: (@tagname) ->
  
  length: -> 1
  
  clone: -> new @constructor @tagname

class OpenEntity extends TagOperation

class CloseEntity extends TagOperation

class DeleteCloseEntity extends TagOperation
    
class DeleteOpenEntity extends TagOperation

# # Annotation Operations
class AnnotationOperation extends Operation

  length: -> 1

class BeginAnnotation extends AnnotationOperation

  constructor: (@beginKeys, @beginValues) ->

  clone: -> new BeginAnnotation(@beginKeys, @beginValues)

class DeleteBeginAnnotation extends AnnotationOperation

  constructor: (@beginKeys) ->

  clone: -> new DeleteBeginAnnotation(@beginKeys)

class EndAnnotation extends AnnotationOperation

  constructor: (@endKeys) ->

  clone: -> new EndAnnotation(@endKeys)

class DeleteEndAnnotation extends AnnotationOperation

  constructor: (@endKeys) ->

  clone: -> new DeleteEndAnnotation(@endKeys)


class OperationBuffer
  # FIXME: Don't send RETAIN fulltext over the wire
  
  CONSTRUCTORS = 
    INSERT: InsertCharacters
    DELETE: DeleteCharacters
    RETAIN: Retain
    BEGIN_ANNOTATION: BeginAnnotation
    DELETE_BEGIN_ANNOTATION: DeleteBeginAnnotation
    END_ANNOTATION: EndAnnotation
    DELETE_END_ANNOTATION: DeleteEndAnnotation
    OPEN_ENTITY: OpenEntity
    DELETE_OPEN_ENTITY: DeleteOpenEntity
    CLOSE_ENTITY: CloseEntity
    DELETE_CLOSE_ENTITY: DeleteCloseEntity
  
  @decode: (encodedBuffer) ->
    operations = []
    
    for [flag, data] in encodedBuffer.operations
      opperations.push new CONSTRUCTORS[flag](data)

    decodedBuffer = new this(operations, encodedBuffer.id)
    decodedBuffer.parentId = encodedBuffer.parentId
    return decodedBuffer
    
  
  constructor: (@operations = [], @id = uniq()) ->
  
  toString: ->
    out = ""
    for operation in @operations
      out += operation.characters
    
    out
  
  length: ->
    sum = 0
    for operation in @operations
      sum += switch operation.constructor
        when InsertCharacters, Retain
          operation.length()
        else
          0
    sum
  
  changeInSizeToIndex: (index) ->
    change = 0
    for operation in @operations
      switch operation.constructor
        when DeleteCharacters
          change -= operation.length()
        when InsertCharacters
          change += operation.length()
        else
          null
      break if @at(index) is operation
    
    change
  
  position: (operation) ->
    start = @indexOf(operation)
    return {
      length: operation.length()
      start: start
      end: start + operation.length()
    }
  
  operationBridgesPosition: (operation, index) ->
    position = @position(operation)
    
    position.start < index < position.end
  
  clone: () ->
    cloned = new OperationBuffer(item.clone() for item in @operations)

  exec: (fn) ->
    fn.call this
    return this
    
  encode: ->
    encoding = {id: @id, parentId: @parentId}
    operations = encoding.operations
    
    encoding.operations = (operation.encode() for operation in @operations)
          
    encoding
  
  # Begin on -1 index so the first member will match up with the zero index
  at: (index) ->
    limit = -1
    for operation in @operations
      if (limit += operation.length()) >= index
        found = operation
        break 
    
    found

  # Operation buffer calculates the index of its members taking into account
  # that insert/delete/retain operations may have length greater than 1.
  indexOf: (anOperation) ->
    position = 0
    for operation in @operations
      break if anOperation is operation
      position += operation.length()

    position
  
  insertOperation: (operation, position) ->
    @operations.splice position, 0, operation
    @mendSeam(position)
  
  findOperationByType: (position, constructor) ->
    operation = @at(position)
    if operation instanceof constructor
       operation
    else
      null
  
  searchableOperations = [
    CharacterOperation, Retain
    BeginAnnotation, EndAnnotation
    OpenEntity, CloseEntity
  ]
  
  for operationClass in searchableOperations
    @::["find#{operationClass.name}"] = (position) ->
      @findCharacterOperationAt(position, operationClass)
      
  insertCharacters: (characters) ->
    @operations.push new InsertCharacters(characters)
  
  deleteCharacters: (characters) ->
    @operations.push new DeleteCharacters(characters)
  
  retain: (characters) ->
    @operations.push new Retain(characters)

  # Insert characters at a position in the buffer. If there is an existing
  # insert operation we add these characters to the operation. If there is a
  # retain
  insertCharactersAt: (characters, position) ->
    if operation = @findCharacterOperationAt(position - 1)
      offset = position - @indexOf(operation)
      operation.insert(characters, offset)
    else if operation = @findRetainOperationAt(position - 1)
      offset = position - @indexOf(operation)
      operation.splice_at(characters, offset)
    else
      @insertOperation new InsertCharacters(characters), position

  # Delete characters at a position in the buffer.
  # Throws an error if there aren't characters at the position requested.
  deleteCharactersAt: (characters, position) ->
    operation = @findCharacterOperationAt(position)
    unless operation
      throw new Error [
        "IllegalCharacterDeletion", characters, "at position:", position, 
        "expected CharacterBasedOperation, got", operation, "instead."
      ]
    offset = position - @indexOf(operation)

    operation.slice_at characters, offset
    @removeOperation(operation) if operation.empty()

  beginAnnotationAt: (beginKeys, beginValues, position) ->
    operation = @at(position)
    if @operationBridgesPosition(operation, position)
      offset = position - @indexOf(operation)
      @spliceOperation(operation, offset)

    @insertOperation new BeginAnnotation(beginKeys, beginValues), position

  endAnnotationAt: (endKeys, position) ->
    operation = @at(position)
    if @operationBridgesPosition(operation, position)
      offset = position - @indexOf(operation)
      @spliceOperation(operation, offset)

    @insertOperation new EndAnnotation(endKeys), position
  
  deleteBeginAnnotationAt: (beginKeys, position) ->
    operation = @findBeginAnnotationAt(position)
    unless operation
      throw new Error [
        "Illegal BeginAnnotation deletion. Expected a BeginAnnotation operation
         at #{position}, but found #{operation} instead."
      ]
    
    @removeOperation(operation)
  
  deleteEndAnnotationAt: (endKeys, position) ->
    operation = @findEndAnnotationAt(position)
    unless operation
      throw new Error [
        "Illegal EndAnnotation deletion. Expected an EndAnnotation operation
         at #{position}, but found #{operation} instead."
      ]
      
    @removeOperation(operation)
  
  openEntityAt: (tagname, position) ->
    operation = @at(position)
    if @operationBridgesPosition(operation, position)
      offset = position - @indexOf(operation)
      @spliceOperation(operation, offset)
    
    @insertOperation new OpenEntity(tagname), position
  
  closeEntityAt: (tagname, position) ->
    operation = @at(position)
    if @operationBridgesPosition(operation, position)
      offset = position - @indexOf(operation)
      @spliceOperation(operation, offset)
    
    @insertOperation new CloseEntity(tagname), position
    
  deleteOpenEntityAt: (tagname, position) ->
    operation = @findOpenEntityOperationAt(position)
    unless operation
      throw new Error [
        "Illegal OpenEntity deletion. Expected an OpenEntity operation
         at #{position}, but found #{operation} instead."
        
      ]
      
    @removeOperation(operation)
  
  deleteCloseEntityAt: (tagname, position) ->
    operation = @findCloseEntityOperationAt(position)
    unless operation
      throw new Error [
        "Illegal CloseEntity deletion. Expected an CloseEntity operation
         at #{position}, but found #{operation} instead."
      ]
      
    @removeOperation(operation)
    
  replace: (operation, replacement) ->
    index = @indexOf(operation)
    @operations.splice(index, 1, replacement)
    @mendSeam()
  
  removeOperation: (anOperation) ->
    newOperations = []
    index = @indexOf(anOperation)
    
    for operation in @operations
      continue if operation is anOperation
      newOperations.push operation

    @operations = newOperations
    
    @mendSeam(index)
  
  mendSeam: (index) ->
    [left, right] = [@at(index - 1), @at(index)]
    
    return if left is right is undefined
    return unless left.constructor is right.constructor
    
    left.merge(right)
    @removeOperation(right)

class DocumentBuffer extends OperationBuffer
  # THERE IS NO FUCKING CLONING OF A DOCUMENT BUFFER
  clone: -> return this

class OperationBufferPair
  flatten = (array) ->
    flat = new Array
    for atom in array
      if atom instanceof Array
        flat.concat flatten(atom)
      else
        flat.push atom
    flat
  
  NullEmitter = emit: ->
  
  constructor: (bufferA, bufferB, @emitter=NullEmitter) ->
    @bufferA = bufferA.clone()
    @bufferB = bufferB.clone()
  
  call: (args) ->
    @cursor = 0
    for operation in @bufferB.operations
      @["visit#{operation.constructor.name}"](operation)
      @emit(operation.constructor.name.toLowerCase(), operation)
      
    unless @cursor is @bufferB.length()
      throw new Error [
        "While composing OperationBuffer ", @bufferB,
        "into OperationBuffer ", @bufferA, "final composed buffer length
         was longer/shorter than expected. Expected #{@bufferB.length()}, got #{@cursor}."
      ]
      
    @bufferA.operations = flatten(@bufferA.operations)
    @bufferA

class OperationBufferTransformer# extends OperationBufferPair
  constructor: (@bufferA, @bufferB) ->
    
  transform: -> [@aPrime(), @bPrime()]
  
  aPrime: -> new OperationBufferTransformer._OperationBufferPair(@bufferA, @bufferB).prime()

  bPrime: -> new OperationBufferTransformer._OperationBufferPair(@bufferB, @bufferA).prime()

class OperationBufferTransformer._OperationBufferPair extends OperationBufferPair
  @::prime = @::call
  
  # We take our pattern, and turn it into a regex.
  @transformers = []
  @transformer: (operationA, conditions, operationB, fn) ->
    # If any part of the pattern is an array, join it with | for the regex
    operationA = operationA.join("|") if operationA instanceof Array
    conditions = conditions.join("|") if conditions instanceof Array
    operationB = operationB.join("|") if operationB instanceof Array
    
    regex = new RegExp("(#{operationA})(#{conditions})(#{operationB})")
    
    @transformers.push [regex, fn]
  
  # Plentey of patterns have no effect. 
  # Use the handy-dandy identityTransformer.
  # FIXME: this is less fun now.
  @identityTransformer: (args...) -> 
    args.push (operation, catalyst) -> operation
    @transformer.apply(this, args)

  ANY_OP = [INSERT, DELETE, RETAIN]
  ANY_RELATION = "before within after wrapping".split " "
  @identityTransformer ANY_OP, "before", [INSERT, DELETE]
  @identityTransformer RETAIN, "within", ANY_OP
  @identityTransformer RETAIN, ["wrapping", "after"], [INSERT, DELETE]
  @identityTransformer ANY_OP, ["before", "after", "wrapping"], RETAIN
  @identityTransformer [INSERT, DELETE], "within", RETAIN
  
    
  @identityTransformer INSERT, ["wrapping"], [INSERT, DELETE]
  
  @transformer INSERT, ["after", "within"], INSERT, (operation, catalyst) ->
    [new Retain(catalyst.length()), operation]
    
  # I'm pretty sure we get to do this because
  # we aren't tracking position for operations.
  # If you delete before me, I don't give a hoot.
  @identityTransformer INSERT, ["after", "within"], DELETE#, (operation, catalyst)
    # @shift -1 * catalyst.length()
  
  # @identityTransformer DELETE, "before", ANY_OP
  
  # Let the latter operation do the deletion.
  @transformer DELETE, "within", DELETE, (operation, catalyst) ->
    new Retain(@operation.length())
    
  # Inverse of within, let the wrapping operation do the deletion.
  @identityTransformer DELETE, "wrapping", DELETE
    
  @identityTransformer DELETE, "after", DELETE, (operation, catalyst) ->
    
  @transformer DELETE, "within", INSERT, (operation, catalyst) ->
    [new Retain(catalyst.length()), operation]
  
  @transformer DELETE, "after", INSERT, (operation, catalyst) ->
    [new Retain(catalyst.length()), operation]
  
  @transformer DELETE, "wrapping", INSERT, (operation, catalyst) ->
    offset = catalyst.start() - @start()
    
    [
      new DeleteCharacters(@characters.slice 0, offset), 
      new Retain(catalyst.characters),
      new DeleteCharacters(@characters.slice offset)
    ]
  
  determineCondition: (operation, catalyst) ->

    if operation.end < catalyst.start 
      "before"
    else if operation.start >= catalyst.start and operation.end <= catalyst.end
      "within"
    else if operation.start < catalyst.start and operation.end > catalyst.end
      "wrapping"
    else if operation.start > catalyst.end
      "after"
  
  transform: (catalyst) ->
    operation = @bufferA.at(@cursor)
    
    operationPosition = @bufferA.position(operation)
    catalystPosition = @bufferB.position(catalyst)
    
    condition = @determineCondition(operationPosition, catalystPosition)
    
    signature = [operation.constant, condition, INSERT].join("")
    
    for [regex, fn] in @constructor.transformers
      break if signature.match(regex)
    
    # FIXME, put these INTO @bufferA!!!
    @bufferA.replace operation, fn.call(operationPosition, catalystPosition)
    
    @cursor += catalyst.length()
  
  visitInsertCharacters: @::transform
  visitDeleteCharacters: @::transform
  visitRetain: @::transform
  
  
class OperationBufferComposer extends OperationBufferPair
  @::compose = @::call
  
  visitInsertCharacters: (insertion) ->
    @bufferA.insertCharactersAt(insertion.characters, @cursor)
    @cursor += insertion.length()
  
  visitDeleteCharacters: (deletion) ->
    @bufferA.deleteCharactersAt(deletion.characters, @cursor)
  
  visitBeginAnnotation: (operation) ->
    @bufferA.beginAnnotationAt(operation.beginKeys, operation.beginValues, @cursor)
    @cursor += operation.length()
    
  visitEndAnnotation: (operation) ->
    @bufferA.endAnnotationAt(operation.beginKeys, @cursor)
    @cursor += operation.length()
    
  visitDeleteBeginAnnotation: (operation) ->
    @bufferA.deleteBeginAnnotationAt(@cursor)
    
  visitDeleteEndAnnotation: (operation) ->
    @bufferA.deleteEndAnnotationAt(@cursor)
    
  visitOpenEntity: (operation) ->
    @bufferA.openEntityAt(operation.tagname, @cursor)
    @cursor += operation.length()
    
  visitDeleteOpenEntity: (operation) ->
    @bufferA.openEntityAt(operation.tagname, @cursor)

  visitCloseEntity: (operation) ->
    @bufferA.closeEntityAt(operation.tagname, @cursor)
    @cursor += operation.length()
    
  visitDeleteCloseEntity: (operation) ->
    @bufferA.deleteCloseEntityAt(operation.tagname, @cursor)

  visitRetain: (retainer) ->
    @cursor += retainer.length()

namespace = if exports?
  exports
else
  window.OT = {}

namespace.uniq = uniq
namespace.Document = Document
namespace.Server = Server
namespace.Client = Client
namespace.OperationBuffer = decode: OperationBuffer.decode
namespace.OperationBufferTransformer = OperationBufferTransformer

namespace.INSERT                     = INSERT
namespace.DELETE                     = DELETE
namespace.RETAIN                     = RETAIN

namespace.BEGIN_ANNOTATION           = BEGIN_ANNOTATION
namespace.DELETE_BEGIN_ANNOTATION    = DELETE_BEGIN_ANNOTATION
namespace.END_ANNOTATION             = END_ANNOTATION
namespace.DELETE_END_ANNOTATION      = DELETE_END_ANNOTATION

namespace.OPEN_ENTITY                = OPEN_ENTITY
namespace.DELETE_OPEN_ENTITY         = DELETE_OPEN_ENTITY
namespace.CLOSE_ENTITY               = CLOSE_ENTITY
namespace.DELETE_CLOSE_ENTITY        = DELETE_CLOSE_ENTITY

namespace.CONSTANT_NAMES = {}

namespace.CONSTANT_NAMES[INSERT] = "INSERT"
namespace.CONSTANT_NAMES[DELETE] = "DELETE"
namespace.CONSTANT_NAMES[RETAIN] = "RETAIN"

namespace.CONSTANT_NAMES[BEGIN_ANNOTATION]        = "BEGIN_ANNOTATION"
namespace.CONSTANT_NAMES[DELETE_BEGIN_ANNOTATION] = "DELETE_BEGIN_ANNOTATION"
namespace.CONSTANT_NAMES[END_ANNOTATION]          = "END_ANNOTATION"
namespace.CONSTANT_NAMES[DELETE_END_ANNOTATION]   = "DELETE_END_ANNOTATION"

namespace.CONSTANT_NAMES[OPEN_ENTITY]             = "OPEN_ENTITY"
namespace.CONSTANT_NAMES[DELETE_OPEN_ENTITY]      = "DELETE_OPEN_ENTITY"
namespace.CONSTANT_NAMES[CLOSE_ENTITY]            = "CLOSE_ENTITY"
namespace.CONSTANT_NAMES[DELETE_CLOSE_ENTITY]     = "DELETE_CLOSE_ENTITY"

if __filename?.match(/operational_transformation.coffee/)
  namespace.lookups = lookups = {}
  operations = [INSERT, DELETE, RETAIN, BEGIN_ANNOTATION, 
    DELETE_BEGIN_ANNOTATION, END_ANNOTATION, DELETE_END_ANNOTATION,
    OPEN_ENTITY, DELETE_OPEN_ENTITY, CLOSE_ENTITY, DELETE_CLOSE_ENTITY]
  for operation in operations
    for relation in ["before", "within", "after", "wrapping"]
      for catalyst in operations
        lookups["#{operation}#{relation}#{catalyst}"] = [operation, relation, catalyst]

  # console.log OperationBufferTransformer._OperationBufferPair.transformers
  # 
  # for lookup, matches of lookups
  #   for [regex, fn] in OperationBufferTransformer._OperationBufferPair.transformers
  #     matches.push(fn) if lookup.match(regex)
  # 
  console.log lookups

  keys = (key for key, value of lookups)
  console.log keys.length
  
  values = (value for key, value of lookups)
  console.log JSON.stringify(values)
  