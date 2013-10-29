document.coffee
===============

A toy ORM for mongodb.

```coffee

Document = require 'document'

class MyDocument extends Document("my_collection")
  @unique { title: 1 }
  jazz: -> "hands!"

Document.connect "mongodb://..."

new MyDocument( title: "My First Document" ).save()

MyDocument.getOrCreate( title: "My First Document" ).wait (err, doc) ->
  doc.jazz() # hands!

```
