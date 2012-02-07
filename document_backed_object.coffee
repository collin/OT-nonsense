## Document Backed Object
# How to back a regular looking AS.Model on an OT document?

# client = new OT.Client
# 
# class SomeThing extends OTObject
# 
# one = new SomeThing(client)

# We've got to do silly things like:
# ooohhhhh....wtf :(
# Let's say you've got multiple representations of something.
# Mulitple editable representations of something.
# And you've got it selected in both.

# InputA, InputB
# [      ]
# [      ]
# Annotations will have to work very hard here.

class OTMutationTranslator
  DOCUMENT_EVENTS = "retain insertcharacters deletecharacters openentity 
    deleteopenentity closeentity deletecloseentity".split(/\s+/)

  constructor: (@document, @object) ->
    
    @contextStack = []
    @currentContext = null
    
    
    for event in DOCUMENT_EVENTS
      @document.on event, @[event]
  
  propertyOperatedOn: (operation) =>
    for propertyName, [leftBound, rightBound] in @object.propertyOperations
      if @document.operationWithinBounds operation, leftBound, rightBound
        return [propertyName, leftBound, rightBound] 

    [null, null, null]
    
  retain: (operation) =>
    # do nothing I suppose

  insertcharacters: (operation) =>
    [propertyName, leftBound, rightBound] = @propertyOperatedOn(operation)
    @object[propertyName] @document.toString(leftBound, rightBound)
    @object.emit "insertcharacters", propertyName, operation

  deletecharacters: (operation) =>
    [propertyName, leftBound, rightBound] = @propertyOperatedOn(operation)
    @object[propertyName] @document.toString(leftBound, rightBound)
    @object.emit "deletecharacters", propertyName, operation
    
  openentity: (operation) =>
    # are we in a property?
    # if not start a new property.
  deleteopenentity: (operation) =>
    # are we in a property?
    # if so, it's time to delete that shite
    # otherwise, figure outwhat property you're in
    # delete the openentity, fire some event
  
  closeentity: (operation) =>
    # are we in a property?
    # if not start a new property.
    # is this the matching close?
    # write that property out
  deletecloseentity: (operation) =>
    # are we in a property?
    # if so, it's time to delete that shite
    # otherwise, figure outwhat property you're in
    # delete the closeentity, fire some event
    

class OT.Model extends AS.Model
  @createFromBuffer: (operationBuffer) ->
    model = new this
    contextStack = []
    attributeContext = null
    attributeBuffer = null
    
    for operation in operationBuffer.operations
      if attributeBuffer
        attributeBuffer.push operation
      
      switch operation.constructor.constant
        when OT.RETAIN
          throw new Error("Should not see RETAIN in createFromBuffer. Use a document buffer, not an operation buffer")
        when OT.DELETE
          throw new Error("Should not see DELETE in createFromBuffer. Use a document buffer, not an operation buffer")
        when OT.DELETE_BEGIN_ANNOTATION
          throw new Error("Should not see DELETE_BEGIN_ANNOTATION in createFromBuffer. Use a document buffer, not an operation buffer")
        when OT.DELETE_END_ANNOTATION  
          throw new Error("Should not see DELETE_END_ANNOTATION in createFromBuffer. Use a document buffer, not an operation buffer")
        when OT.DELETE_OPEN_ENTITY     
          throw new Error("Should not see DELETE_OPEN_ENTITY in createFromBuffer. Use a document buffer, not an operation buffer")
        when OT.DELETE_CLOSE_ENTITY    
          throw new Error("Should not see DELETE_CLOSE_ENTITY in createFromBuffer. Use a document buffer, not an operation buffer")

        when OT.INSERT
          # pass
          
        when OT.OPEN_ENTITY
          contextStack.push operation
          attributeContext ?= operation
          attributeBuffer ?= []
        when OT.CLOSE_ENTITY
          contextStack.pop()
          if contextStack is []
            model.set_attribute(attributeContext.tagName, attributeBuffer)
            model.propertyOperations[attributeContext.tagName] = [attributeContext, operation]
            attributeContext = null
            attributeBuffer = null
  
  constructor: (@client) ->
    @document = new OT.Document
    @client.addDocument(@document)
    @translator = new OTMutationTranslator(this, @document)
    super
      
  applyLocalOperation: (fn) ->
    client.applyLocalOperation document, -> fn(this)

  # applyRemoteOperation: (buffer) ->
  #   contextStack = []
  #   attributeContext = null
  #   attributeBuffer = null
  #   
  #   for operation in buffer.operations
  #     switch operation.constructor.constant
  #       when OT.RETAIN
  #       when OT.DELETE
  #       when OT.DELETE_BEGIN_ANNOTATION
  #       when OT.DELETE_END_ANNOTATION
  #       when OT.DELETE_OPEN_ENTITY
  #       when OT.DELETE_CLOSE_ENTITY
  #       when OT.INSERT
  #       when OT.OPEN_ENTITY
  #       when OT.CLOSE_ENTITY
  #   
  set_attribute: (name, value) ->
    super
    
    [openOperation, closeOperation] = @propertyOperations[property]
    
    @applyLocalOperation ->
      if index = @indexOf(openOperation) >= 0
        # Property already exists, we'll get to it,
        # clear out the data and replace it. Retaining everything else.
        @retainThroughOperation(openOperation)
        @deleteToOperation(closeOperation)
        # FIXME: potentially a blob of text, need to OT that
        # (with selection annotation.)
        @insertCharacters(value)
        @retainFromOperation(closeOperation)
      else
        # Property doesn't exist, we'll stick it in the end of the document.
        @retainAll()
        _openOperation = @openEntity()
        @insertCharacters(value)
        _closeOperation = @closeEntity()
        @propertyOperations[property] = [_openOperation, _closeOperation]
      
