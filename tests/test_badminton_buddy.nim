## Integration coverage for the current Badminton repository and page API.
## Run with -p:external -d:harding_sqlite; add -d:mummyx for HTTP coverage.

import std/unittest

when defined(harding_sqlite):
  import std/strutils
  import ../src/harding/core/[types, scheduler]
  import ../src/harding/interpreter/vm

  proc newBadmintonInterp(): Interpreter =
    let ctx = newSchedulerContext()
    result = ctx.mainProcess.getInterpreter()
    loadStdlib(result)
    let (_, err) = result.evalStatements("""
      Harding load: "lib/web/Bootstrap.hrd".
      Harding load: "badminton-buddy/Models/User.hrd".
      Harding load: "badminton-buddy/Models/Court.hrd".
      Harding load: "badminton-buddy/Models/TimeSlot.hrd".
      Harding load: "badminton-buddy/Models/Booking.hrd".
      Harding load: "badminton-buddy/Models/PartnerRequest.hrd".
      Harding load: "badminton-buddy/Repository.hrd".
      Harding load: "badminton-buddy/BadmintonApp.hrd".
      Repo := BadmintonRepository open: ":memory:".
      App := BadmintonApp basicNew.
      App::repository := Repo.
      App::daisy := Daisy withCDN.
    """)
    if err.len > 0:
      raise newException(ValueError, err)

  when defined(mummyx):
    import std/[httpclient, net, os, osproc, streams, times]

    if paramCount() == 2 and paramStr(1) == "--badminton-http":
      var serverInterp = newBadmintonInterp()
      let (_, err) = serverInterp.evalStatements("""
        Harding load: "lib/mummyx/Bootstrap.hrd".
        App::router := Router new.
        App installRoutes.
        Server := HttpServer new.
        Server router: App::router.
        Server serveForever: """ & paramStr(2))
      if err.len > 0:
        stderr.writeLine(err)
        quit(1)
      quit(0)

  let sharedInterp = newBadmintonInterp()

  suite "Badminton Buddy - Repository":
    var interp: Interpreter
    setup:
      interp = sharedInterp
    teardown:
      let (_, err) = interp.evalStatements("Repo close. Repo := BadmintonRepository open: \":memory:\". App::repository := Repo")
      require(err.len == 0)

    test "in-memory SQLite connection and demo courts":
      let (value, err) = interp.doit("(Repo connection isConnected) and: [ Repo allCourts size = 3 ]")
      require(err.len == 0)
      require(value.kind == vkBool)
      check(value.boolVal)

    test "seeded user and time slots":
      let (value, err) = interp.doit("(Repo currentUser notNil) and: [ (Repo slotsForCourt: (Repo allCourts at: 0) id) size = 6 ]")
      require(err.len == 0)
      require(value.kind == vkBool)
      check(value.boolVal)

    test "booking is created and duplicate reservation is rejected":
      let (_, err) = interp.evalStatements("""
        Slot := (Repo slotsForCourt: (Repo allCourts at: 0) id) at: 0.
        Booking1 := Repo createBookingForSlot: Slot id userId: Repo currentUser id.
        Duplicate := Repo createBookingForSlot: Slot id userId: Repo currentUser id.
      """)
      require(err.len == 0)
      let (value, verifyErr) = interp.doit("Booking1 notNil and: [ Duplicate isNil and: [ (Repo bookingsForUser: Repo currentUser id) size = 1 ] ]")
      require(verifyErr.len == 0)
      require(value.kind == vkBool)
      check(value.boolVal)

    test "cancelled booking is updated in memory and SQLite":
      let (_, err) = interp.evalStatements("""
        Slot := (Repo slotsForCourt: (Repo allCourts at: 0) id) at: 0.
        Booking1 := Repo createBookingForSlot: Slot id userId: Repo currentUser id.
        Repo cancelBooking: Booking1 id.
        Repo loadBookings.
      """)
      require(err.len == 0)
      let (value, verifyErr) = interp.doit("(Repo bookingById: Booking1 id) status = \"cancelled\"")
      require(verifyErr.len == 0)
      require(value.kind == vkBool)
      check(value.boolVal)

  suite "Badminton Buddy - Pages":
    test "current page methods render seeded data and Daisy theme":
      var interp = sharedInterp
      for (selector, expected) in [("homePage", "Find Courts"),
                                    ("courtsPage", "City Sports Hall"),
                                    ("bookingsPage", "My Bookings"),
                                    ("partnersPage", "Find a Partner")]:
        let (value, err) = interp.doit("App " & selector)
        require(err.len == 0)
        require(value.kind == vkString)
        check(expected in value.strVal)
        check("data-theme='business'" in value.strVal)

  when defined(mummyx):
    suite "Badminton Buddy - HTTP":
      test "owned server serves routes and returns 404 for an unknown route":
        # Reserve an ephemeral loopback port, then release it for the child.
        let socket = newSocket()
        socket.bindAddr(Port(0), "127.0.0.1")
        let port = socket.getLocalAddr()[1]
        socket.close()
        let logPath = "build/badminton-http-test.log"
        createDir("build")
        let child = startProcess(getAppFilename(),
          args = @["--badminton-http", $port], options = {})
        defer:
          if child.running(): child.terminate()
          discard child.waitForExit(2000)
          writeFile(logPath, child.outputStream.readAll())
          child.close()
        let baseUrl = "http://127.0.0.1:" & $port
        var ready = false
        let deadline = epochTime() + 15.0
        while epochTime() < deadline and child.running():
          let client = newHttpClient(timeout = 1000)
          try:
            ready = client.get(baseUrl & "/").code == Http200
          except CatchableError:
            discard
          finally:
            client.close()
          if ready: break
          sleep(50)
        require(ready)
        for (path, expected) in [("/", "Badminton Buddy"),
                                 ("/courts", "City Sports Hall"),
                                 ("/bookings", "My Bookings"),
                                 ("/partners", "Find a Partner")]:
          let client = newHttpClient(timeout = 2000)
          defer: client.close()
          let response = client.get(baseUrl & path)
          check(response.code == Http200)
          check(response.body.contains(expected))
        let client = newHttpClient(timeout = 2000)
        defer: client.close()
        check(client.get(baseUrl & "/courts/99999").code == Http404)
  else:
    suite "Badminton Buddy - HTTP":
      test "requires MummyX support (-d:mummyx)":
        skip()
else:
  suite "Badminton Buddy":
    test "requires SQLite support (-d:harding_sqlite)":
      skip()
