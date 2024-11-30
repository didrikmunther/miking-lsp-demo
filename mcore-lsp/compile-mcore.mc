include "../miking-lsp/dsl/lsp-server.mc"
include "../../miking/src/main/eval.mc"

-- let compileFunc =
--   -- : use MExprAst in String -> String -> Either [(Info, String)] (Expr, LSPImplementations)
--     lam uri. lam content.
--       use ExtMCore in
  
--       eprintln "Parsing Mcore program";
--       eprintln uri;
  
--       let strippedUri = stripUriProtocol uri in
  
--       let ast = parseParseMCoreFile {
--         keepUtests = false,
--         keywords = [],
--         pruneExternalUtests = true,
--         pruneExternalUtestsWarning = true,
--         findExternalsExclude = false, -- the interpreter does not support externals
--         eliminateDeadCode = false
--       } strippedUri in
      
  
--         -- If option --debug-parse, then pretty print the AST
--         -- printLn (mexprToString ast);
  
--       --   let ast = makeKeywords ast in
  
--       --   let ast = symbolize ast in
  
--       --   let ast =
--       --     if options.debugProfile then
--       --       instrumentProfiling ast
--       --     else ast
--       --   in
  
--       --   let ast =
--       --     removeMetaVarExpr
--       --       (typeCheckExpr
--       --         {typcheckEnvDefault with
--       --           disableConstructorTypes = not options.enableConstructorTypes}
--       --         ast)
--       --   in
--       --   (if options.debugTypeCheck then
--       --     printLn (use TyAnnotFull in annotateMExpr ast) else ());
  
--       --   -- If option --test, then generate utest runner calls. Otherwise strip away
--       --   -- all utest nodes from the AST.
--       --   let ast = generateUtest options.runTests ast in
--       --   if options.exitBefore then exit 0
--       --   else
--       --     eval (evalCtxEmpty ()) (updateArgv args ast); ()
--       -- in
--       -- iter evalFile files
  
--       -- use Rtppl in
  
--       -- eprintln "Parsing Mcore program";
--       -- let program = parseRtpplExn uri content in
--       -- eprintln "Parsed Mcore program";
  
--       -- match program with ProgramRtpplProgram p in
  
--       -- match compileRtpplToExpr options p.tops with (llSolutions, topEnv, coreExpr) in
--       -- eprintln "Compiled RTPPL program";
  
--       -- -- let exprs = compileRtpplProgram options program in
--       -- -- let expr = (head (mapToSeq exprs)).1 in
  
  
--       let implementations: LSPImplementations = {
--         hover=[]
--       } in
--       -- let implementations = foldl (
--       --   lam acc. lam x.
--       --     { hover=join [acc.hover, x.hover] }
--       --   ) lsp lspResult
--       -- in
  
--       -- Right (coreExpr, implementations)
  
--       Right (ast, implementations)

let compileFunc = lam debug. lam uri.
  -- : use MExprAst in String -> String -> Either [(Info, String)] (Expr, LSPImplementations)
  use ExtMCore in

  (if debug then eprintln (join ["Parsing Mcore program: ", uri]); () else ());

  let strippedUri = stripUriProtocol uri in

  let expr = parseParseMCoreFile {
    keepUtests = false,
    keywords = [],
    pruneExternalUtests = true,
    pruneExternalUtestsWarning = true,
    findExternalsExclude = false, -- the interpreter does not support externals
    eliminateDeadCode = false
  } strippedUri in

  (if debug then eprintln "Make keywords"; () else ());
  let expr = use KeywordMaker in makeKeywords expr in

  (if debug then eprintln "Symbolizing"; () else ());
  let expr = symbolizeAllowFree expr in
  -- eprintln (join ["Symbolized: ", use MExprPrettyPrint in expr2str expr, "\n"]);

  -- (Note Didrik): Type checking takes several minutes to run. Disabling for now.
  (if debug then eprintln "Type checking"; () else ());
  let expr = removeMetaVarExpr (typeCheckExpr typcheckEnvDefault expr) in
  -- let expr = use TypeCheck in typeCheckExpr typcheckEnvDefault expr in
  -- let expr = typeCheckExpr typcheckEnvDefault expr in

  let implementations: LSPImplementations = {
    hover=[]
  } in

  Right (expr, implementations)

mexpr

-- Compile an MCore program

-- Possible errors:
-- ERROR </Users/didrik/projects/miking/lsp-demo/miking-lsp/test.mc 6:7-6:10>: Unknown variable 'abc'
-- Fatal error: exception Sys_error("/Users/didrik/projects/miking/lsp-demo/miking-lsp/tesat.mc: No such file or directory")

let uri = get argv 1 in
compileFunc false uri;
()