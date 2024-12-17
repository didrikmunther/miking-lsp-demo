include "json.mc"
include "mexpr/info.mc"
include "ext/file-ext.mc"
include "result.mc"

-- returns Option content if the requested number of bytes could be read
-- otherwise, None is returned
recursive
  let readBytesBuffered : ReadChannel -> Int -> Option [Int] =
    lam rc. lam len. switch fileReadBytes rc len
      case Some s then (
        let actualLength = length s in
        if eqi actualLength len then Some s
        else match readBytesBuffered rc (subi len actualLength)
          with Some s2 then Some (join [s, s2])
          else None ()
      )
      case None () then None ()
    end
  end

recursive let reduce: all a. all b. (b -> a -> b) -> b -> [a] -> b =
  lam f. lam acc. lam xs.
    match xs with [x] ++ xs then
      reduce f (f acc x) xs
    else
      acc
end

let groupBy: all k. all v. (k -> k -> Int) -> (v -> k) -> [v] -> Map k [v] =
  lam cmp. lam f. lam arr.
    foldl
      (lam m. lam v. mapInsertWith concat (f v) [v] m)
      (mapEmpty cmp)
      arr

let eprint: String -> () = lam s.
  fileWriteString fileStderr s;
  flushStderr()
  
let eprintln: String -> () = lam s.
  fileWriteString fileStderr (join [s, "\n"]);
  flushStderr()

let print: String -> () = lam s.
  fileWriteString fileStdout s;
  flushStdout()

let println: String -> () = lam s.
  fileWriteString fileStdout (join [s, "\n"]);
  flushStdout()

let rpcprint = lam s.
  let len = addi 1 (length s) in
  println (join ["Content-Length: ", int2string len, "\r\n\r\n", s]);
  -- eprintln (join ["Content-Length: ", int2string len, "\r\n\r\n", s]);
  ()

let jsonKeyObject: [(String, JsonValue)] -> JsonValue = lam content.
  JsonObject (
    mapFromSeq cmpString content
  )

let infoWithFilename: String -> Info -> Info =
  lam filename. lam info.
    match info
      with Info r then
        Info {r with filename = filename}
      else
        info

-- Map the errors, if any, inside the `Result`. Preserves all warnings.
let mapErrors
  : all w. all e1. all e2. all a. (e1 -> e2) -> Result w e1 a -> Result w e2 a
  = lam f. lam start.
    switch start
    case ResultOk r then ResultOk r
    case ResultErr { warnings = warnings, errors = errors } then
      let errors = map f (mapValues errors) in
      let f = lam acc. lam err. mapInsert (gensym ()) err acc in
      ResultErr {
        warnings = warnings,
        errors = foldl f (_emptyMap ()) errors
      }
    end