#!/usr/bin/env nim

import std/[unittest, json, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

suite "Json Object Serialization":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "serializes ordinary objects by slot order":
    let (results, err) = interp.evalStatements("""
      Person := Object derivePublic: #(name, age).
      person := Person new.
      person::name := "Alice".
      person::age := 30.
      Result := Json stringify: person.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["name"].getStr() == "Alice"
    check parsed["age"].getInt() == 30

  test "serializes inherited slots":
    let (results, err) = interp.evalStatements("""
      Person := Object derivePublic: #(name).
      Employee := Person derivePublic: #(role).
      employee := Employee new.
      employee::name := "Alice".
      employee::role := "Engineer".
      Result := Json stringify: employee.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["name"].getStr() == "Alice"
    check parsed["role"].getStr() == "Engineer"

  test "supports exclude and rename rules":
    let (results, err) = interp.evalStatements("""
      User := Object derivePublic: #(id, username, password).
      User jsonExclude: #(password);
           jsonRename: #{#username -> "userName"}.
      user := User new.
      user::id := 7.
      user::username := "alice".
      user::password := "secret".
      Result := Json stringify: user.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["id"].getInt() == 7
    check parsed["userName"].getStr() == "alice"
    check not parsed.hasKey("password")

  test "supports jsonOnly and omit rules":
    let (results, err) = interp.evalStatements("""
      Profile := Object derivePublic: #(id, email, avatar, bio).
      Profile jsonOnly: #(id, email, avatar, bio);
              jsonOmitNil: #(avatar);
              jsonOmitEmpty: #(bio).
      profile := Profile new.
      profile::id := 3.
      profile::email := "a@example.com".
      profile::bio := "".
      Result := Json stringify: profile.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["id"].getInt() == 3
    check parsed["email"].getStr() == "a@example.com"
    check not parsed.hasKey("avatar")
    check not parsed.hasKey("bio")

  test "supports explicit field order":
    let (results, err) = interp.evalStatements("""
      Person := Object derivePublic: #(name, age, city).
      Person jsonFieldOrder: #(city, name).
      person := Person new.
      person::name := "Alice".
      person::age := 30.
      person::city := "Portland".
      Result := Json stringify: person.
    """)
    check err.len == 0
    check results[^1].strVal == "{\"city\":\"Portland\",\"name\":\"Alice\",\"age\":30}"

  test "supports rawJson and symbolName formatters":
    let (results, err) = interp.evalStatements("""
      Envelope := Object derivePublic: #(payload, kind).
      Envelope jsonFormat: #{#payload -> #rawJson, #kind -> #symbolName}.
      envelope := Envelope new.
      envelope::payload := "{\"ok\":true}".
      envelope::kind := #status.
      Result := Json stringify: envelope.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["payload"]["ok"].getBool()
    check parsed["kind"].getStr() == "status"

  test "supports string and className formatters":
    let (results, err) = interp.evalStatements("""
      Wrapper := Object derivePublic: #(count, type).
      Wrapper jsonFormat: #{#count -> #string, #type -> #className}.
      wrapper := Wrapper new.
      wrapper::count := 42.
      wrapper::type := Array.
      Result := Json stringify: wrapper.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["count"].getStr() == "42"
    check parsed["type"].getStr() == "Array"

  test "supports jsonRepresentation fallback":
    let (results, err) = interp.evalStatements("""
      Invoice := Object derivePublic: #(id, lines).
      Invoice>>jsonRepresentation [
        ^ #{
          "id" -> id,
          "lineCount" -> lines size
        }
      ].
      invoice := Invoice new.
      invoice::id := 9.
      invoice::lines := #(1, 2, 3, 4).
      Result := Json stringify: invoice.
    """)
    check err.len == 0
    let parsed = parseJson(results[^1].strVal)
    check parsed["id"].getInt() == 9
    check parsed["lineCount"].getInt() == 4

  test "detects jsonRepresentation cycles":
    let (_, err) = interp.evalStatements("""
      Node := Object derivePublic: #(next).
      Node>>jsonRepresentation [
        ^ #{"next" -> next}
      ].
      node := Node new.
      node::next := node.
      Result := Json stringify: node.
    """)
    check err.contains("cycle")

  test "rejects unsupported JSON table keys":
    let (_, err) = interp.evalStatements("""
      BadKey := Object derivePublic: #(id).
      key := BadKey new.
      key::id := 1.
      payload := #{key -> "value"}.
      Result := Json stringify: payload.
    """)
    check err.contains("Unsupported JSON table key")
