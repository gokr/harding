## ============================================================================
## Badminton Buddy Integration Tests
## Tests for the Badminton Buddy web application
## ============================================================================

import std/[unittest, os, strutils, osproc, httpclient, strformat, times]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc newBadmintonInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  initProcessorGlobal(result)
  loadStdlib(result)

  # Load just the models and repository (no HTTP server components)
  var setup = """
    Harding load: "lib/reactive/Bootstrap.hrd".
    Harding load: "badminton-buddy/Models/User.hrd".
    Harding load: "badminton-buddy/Models/Court.hrd".
    Harding load: "badminton-buddy/Models/TimeSlot.hrd".
    Harding load: "badminton-buddy/Models/Booking.hrd".
    Harding load: "badminton-buddy/Models/PartnerRequest.hrd".
    Harding load: "badminton-buddy/Repository.hrd".
  """
  let setupResult = result.evalStatements(setup)
  if setupResult[1].len > 0:
    raise newException(ValueError, setupResult[1])

proc waitForServer(port: int = 8080, timeout: int = 10): bool =
  let client = newHttpClient(timeout = 1000)
  let deadline = getTime() + initDuration(seconds = timeout)

  while getTime() < deadline:
    try:
      let response = client.get(&"http://localhost:{port}/")
      if response.code == Http200:
        return true
    except:
      sleep(100)

  return false

proc stopServer(port: int = 8080) =
  discard execCmdEx(&"lsof -ti:{port} | xargs kill -9 2>/dev/null || true")

suite "Badminton Buddy - Repository":
  test "Repository can be initialized with SQLite":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      repo class name println
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "BadmintonRepository")

  test "Repository seeds demo data":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      courts := repo allCourts
      courts size printString
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "3")  # We seed 3 courts

  test "Repository creates bookings":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      user := repo currentUser
      user isNil ifTrue: [
        "No demo user created" println
      ] ifFalse: [
        courts := repo allCourts
        court := courts at: 0
        slots := repo slotsForCourt: (court id)
        slot := slots at: 0
        booking := repo createBookingForSlot: (slot id) userId: (user id)
        booking isNil ifTrue: [
          "Failed to create booking" println
        ] ifFalse: [
          "Booking created" println
        ]
      ]
      "done"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "done")

  test "Repository cancels bookings":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      user := repo currentUser
      user isNil ifTrue: [
        "No demo user" println
      ] ifFalse: [
        courts := repo allCourts
        court := courts at: 0
        slots := repo slotsForCourt: (court id)
        slot := slots at: 0
        booking := repo createBookingForSlot: (slot id) userId: (user id)
        booking isNil ifTrue: [
          "Failed to create booking" println
        ] ifFalse: [
          cancelled := repo cancelBooking: (booking id)
          cancelled isNil ifTrue: [
            "Failed to cancel" println
          ] ifFalse: [
            "Cancelled" println
          ]
        ]
      ]
      "done"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "done")

suite "Badminton Buddy - Components":
  test "Home page renders":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      page := HomePageComponent repository: repo
      html := page renderString
      html includesSubString: "Find Courts & Partners"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.boolVal == true)

  test "Courts page renders":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      page := CourtsPageComponent repository: repo
      html := page renderString
      html includesSubString: "City Sports Hall"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.boolVal == true)

  test "Bookings page renders":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      page := BookingsPageComponent repository: repo
      html := page renderString
      html includesSubString: "My Bookings"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.boolVal == true)

  test "Partners page renders":
    var interp = newBadmintonInterp()
    let script = """
      repo := BadmintonRepository open: ":memory:"
      page := PartnersPageComponent repository: repo
      html := page renderString
      html includesSubString: "Find a Partner"
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.boolVal == true)

suite "Badminton Buddy - HTTP Endpoints":
  var serverProcess: Process

  setup:
    stopServer(18080)  # Use different port to avoid conflicts
    discard execCmdEx("rm -f badminton-buddy/badminton.db")

  teardown:
    stopServer(18080)
    discard execCmdEx("rm -f badminton-buddy/badminton.db")

  test "Server starts and responds to home page":
    discard execCmdEx("./harding badminton-buddy/server.hrd > /tmp/badminton-server.log 2>&1 &")

    let serverStarted = waitForServer(8080, timeout = 15)
    check serverStarted
    if serverStarted:
      let client = newHttpClient()
      let response = client.get("http://localhost:8080/")
      check(response.code == Http200)
      check(response.body.contains("Badminton Buddy"))
      client.close()

  test "Courts page loads":
    let client = newHttpClient()
    var passed = false
    try:
      let response = client.get("http://localhost:8080/courts")
      check(response.code == Http200)
      check(response.body.contains("Badminton Courts"))
      passed = true
    except:
      passed = false
    finally:
      client.close()
    check passed

  test "Bookings page loads":
    let client = newHttpClient()
    var passed = false
    try:
      let response = client.get("http://localhost:8080/bookings")
      check(response.code == Http200)
      check(response.body.contains("My Bookings"))
      passed = true
    except:
      passed = false
    finally:
      client.close()
    check passed

  test "Partners page loads":
    let client = newHttpClient()
    var passed = false
    try:
      let response = client.get("http://localhost:8080/partners")
      check(response.code == Http200)
      check(response.body.contains("Find a Partner"))
      passed = true
    except:
      passed = false
    finally:
      client.close()
    check passed

  test "Static assets (CSS) loads":
    let client = newHttpClient()
    var passed = false
    try:
      let response = client.get("http://localhost:8080/assets/daisyui.css")
      check(response.code == Http200)
      passed = true
    except:
      passed = false
    finally:
      client.close()
    check passed

  test "404 for unknown court":
    let client = newHttpClient()
    var passed = false
    try:
      let response = client.get("http://localhost:8080/courts/99999")
      check(response.code == Http404)
      passed = true
    except:
      passed = false
    finally:
      client.close()
    check passed
