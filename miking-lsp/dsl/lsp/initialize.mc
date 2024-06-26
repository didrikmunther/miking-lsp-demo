include "json.mc"

include "../utils.mc"
include "./root.mc"

lang LSPInitialize = LSPRoot
	syn Params =
	| Initialized {}
	| Initialize { }

	sem getParams request =
	| "initialized" ->
		Initialized {}
	| "initialize" ->
		Initialize {}

	sem execute context =
	| Initialized {} -> None ()
	| Initialize {} -> Some (
		jsonKeyObject [
			("jsonrpc", JsonString "2.0"),
			("id", JsonInt 0),
			("result", jsonKeyObject [
				("capabilities", jsonKeyObject [
					("diagnosticProvider", jsonKeyObject [
						("interFileDependencies", JsonBool false),
						("workspaceDiagnostics", JsonBool false)
					]),
					("hoverProvider", JsonBool true),
					("textDocumentSync", JsonInt 1),
					("definitionProvider", JsonBool true),
					("typeDefinitionProvider", JsonBool true),
					("completionProvider", jsonKeyObject [
						("triggerCharacters", JsonArray [
							JsonString "."
						])
					])
				]),
				("serverInfo", jsonKeyObject [
					("name", JsonString "miking-lsp-server"),
					("version", JsonString "0.1.0")
				])
			])
		]
	)
end