include "json.mc"
include "mexpr/pprint.mc"

include "../../lib/utils.mc"
include "./utils.mc"

include "./root.mc"
-- include "coreppl::parser.mc"

lang SuperPrettyPrint = MExprPrettyPrint --+ DPPLParser
end

lang LSPHover = LSPRoot
  syn Params =
  | Hover {
    id: Int,
    textDocument: TextDocumentPositionParams
  }

  sem getParams request =
  | "textDocument/hover" ->
    match request.id with Some id in
    Hover {
      id = id,
      textDocument = getTextDocumentPositionParams request.params
    }

  sem execute context =
    | Hover { id = id, textDocument = {
      uri = uri,
      line = line,
      character = character
    } } -> 
      -- let strippedUri = "/mnt/ProbTime/examples/coin/coin.rpl" in
      let strippedUri = stripUriProtocol uri in

      -- Add 1 to incoming line and character to match the 1-based indexing of LSP
      let line = addi line 1 in

      let debugText = join [
        "Uri: ", uri, ", ",
        "Line: ", int2string line, ", Character: ", int2string character, "\n\n"
      ] in

      let environment = mapLookup uri context.environment.files in
      match environment with Some environment then
        let variable = environment.findVariable uri line character in
        let response = match variable with Some ((info, variable, ty)) then
        let info = getFileInfo info in

        jsonKeyObject [
          (
            "contents", JsonString (join [
              "```mikingdsl\n", nameGetStr variable, ": ", use SuperPrettyPrint in type2str ty, "\n```"
            ])
          ),
          ("range", jsonKeyObject [
            ("start", jsonKeyObject [
              ("line", JsonInt (subi info.lineStart 1)),
              ("character", JsonInt info.colStart)
            ]),
            ("end", jsonKeyObject [
              ("line", JsonInt (subi info.lineEnd 1)),
              ("character", JsonInt info.colEnd)
            ])
          ])
        ]
      else
        eprintln "Variable not found";
        jsonKeyObject [(
          "contents", JsonString (join [
            debugText,
            "[nothing found]"
          ])
        )]
        in

        {
          environment = context.environment,
          response = Some(jsonKeyObject [
            ("jsonrpc", JsonString "2.0"),
            ("id", JsonInt id),
            ("result", response)
          ])
        }
      else
        {
          environment = context.environment,
          response = Some(jsonKeyObject [
            ("jsonrpc", JsonString "2.0"),
            ("id", JsonInt id),
            ("result", JsonNull ())
          ])
        }

end