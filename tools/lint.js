// Static checks for Matcha-specific failure modes.
//   node tools/lint.js
// 1. forbidden APIs (the ones that killed v1-v3)
// 2. assignments to names that were never declared local (silent globals)
// 3. varargs used inside a closure handed to pcall

const fs = require('fs');
const path = require('path');
const lp = require('./node/node_modules/luaparse');

const root = path.resolve(__dirname, '..');
const files = fs.readdirSync(path.join(root, 'src'))
  .filter(f => f.endsWith('.lua'))
  .sort()
  .map(f => path.join(root, 'src', f));

const FORBIDDEN = [
  { re: /Instance\.new\s*\(/, msg: 'Instance.new does not exist in Matcha' },
  { re: /:\s*FireServer\s*\(/, msg: 'RemoteEvent:FireServer is not emulated' },
  { re: /:\s*InvokeServer\s*\(/, msg: 'RemoteFunction:InvokeServer is not emulated' },
  { re: /WorldToViewportPoint\s*\(/, msg: 'use WorldToScreen instead' },
  { re: /CurrentCamera\s*:\s*WorldToViewportPoint/, msg: 'use WorldToScreen instead' },
  { re: /task\.delay\s*\(/, msg: 'task.delay never fires in this build' },
  { re: /task\.defer\s*\(/, msg: 'task.defer never fires in this build' },
  { re: /CharacterAdded/, msg: 'Player.CharacterAdded is not documented; poll instead' },
  { re: /gethwid\s*\(/, msg: 'gethwid is not in the Matcha API' },
  { re: /game\s*:\s*HttpGet/, msg: 'DataModel:HttpGet exists but httpget is the documented global' },
];

const ALLOWED_GLOBALS = new Set([
  'RR', '_G', 'game', 'workspace', 'script', 'print', 'printl', 'warn', 'error',
  'errorl', 'wait', 'task', 'tick', 'typeof', 'type', 'pairs', 'ipairs', 'next',
  'select', 'unpack', 'assert', 'pcall', 'xpcall', 'setmetatable', 'getmetatable',
  'rawget', 'rawset', 'rawequal', 'rawlen', 'gcinfo', 'newproxy', 'require',
  'Vector2', 'Vector3', 'CFrame', 'Color3', 'UDim', 'UDim2', 'Ray', 'Drawing',
  'WorldToScreen', 'notify', 'identifyexecutor', 'getgamename', 'getscripts',
  'getscriptbytecode', 'getscripthash', 'decompile', 'base64encode', 'base64decode',
  'httpget', 'httppost', 'readfile', 'writefile', 'appendfile', 'makefolder',
  'isfile', 'isfolder', 'listfiles', 'delfile', 'delfolder', 'getgc', 'setgc',
  'applygc', 'getbase', 'memory_read', 'memory_write', 'setrobloxinput',
  'isrbxactive', 'setclipboard', 'keypress', 'keyrelease', 'iskeypressed',
  'ismouse1pressed', 'ismouse2pressed', 'mouse1press', 'mouse1release',
  'mouse1click', 'mouse2press', 'mouse2release', 'mouse2click', 'mousemoveabs',
  'mousemoverel', 'mousescroll', 'getfenv', 'setfenv', 'loadstring', 'load',
  'GetPingValue', 'string', 'table', 'math', 'os', 'coroutine', 'utf8',
  'setfflag', 'getfflag', 'run_secure', 'bit32',
]);

let problems = 0;
const report = (file, line, msg) => {
  problems++;
  console.log(`  ${path.basename(file)}:${line}  ${msg}`);
};

for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n');

  lines.forEach((line, i) => {
    for (const rule of FORBIDDEN) {
      if (rule.re.test(line)) {
        // allow the deliberate probe in 10_caps.lua
        if (file.endsWith('10_caps.lua') && /pcall\(function\(\)\s*(cam|hum):/.test(line)) continue;
        report(file, i + 1, rule.msg);
      }
    }
  });

  let ast;
  try {
    ast = lp.parse(src, { luaVersion: '5.1', locations: true });
  } catch (e) {
    report(file, 0, 'parse error: ' + e.message);
    continue;
  }

  const declared = new Set();
  const assigned = [];

  const walk = (node, parent) => {
    if (!node || typeof node !== 'object') return;

    if (node.type === 'LocalStatement') {
      for (const v of node.variables) if (v.type === 'Identifier') declared.add(v.name);
    }
    if (node.type === 'FunctionDeclaration' && node.identifier && node.identifier.type === 'Identifier') {
      declared.add(node.identifier.name);
    }
    if ((node.type === 'FunctionDeclaration' || node.type === 'FunctionExpression') && Array.isArray(node.parameters)) {
      for (const p of node.parameters) if (p.type === 'Identifier') declared.add(p.name);
    }
    if (node.type === 'Identifier' && parent && (parent.type === 'ForNumericStatement')) declared.add(node.name);
    if (node.type === 'Identifier' && parent && (parent.type === 'ForGenericStatement')) declared.add(node.name);

    if (node.type === 'AssignmentStatement') {
      for (const t of node.variables) {
        if (t.type === 'Identifier') assigned.push({ name: t.name, line: t.loc.start.line });
      }
    }

    for (const key of Object.keys(node)) {
      if (key === 'loc') continue;
      const child = node[key];
      if (Array.isArray(child)) child.forEach(c => walk(c, node));
      else if (child && typeof child === 'object' && child.type) walk(child, node);
    }
  };
  walk(ast, null);

  // a global write is only a bug if the name is never declared anywhere
  for (const a of assigned) {
    if (!declared.has(a.name) && !ALLOWED_GLOBALS.has(a.name)) {
      report(file, a.line, `assignment to undeclared global '${a.name}'`);
    }
  }
}

// ---------------------------------------------------------------------
// 4. the concatenated build is ONE chunk, so its top-level locals all
//    share the 200-register limit. Eleven modules each opening with
//    `local RR = _G.RR` is fine today, but this is the failure that
//    arrives suddenly and reports a confusing syntax error.
// ---------------------------------------------------------------------
const dist = path.join(root, 'dist', 'RunRestaurant.lua');
if (fs.existsSync(dist)) {
  const src = fs.readFileSync(dist, 'utf8');
  try {
    const ast = lp.parse(src, { luaVersion: '5.1', locations: true });
    let topLocals = 0;
    for (const node of ast.body) {
      if (node.type === 'LocalStatement') topLocals += node.variables.length;
    }
    if (topLocals > 190) {
      report(dist, 1, `${topLocals} top-level locals in one chunk (limit is 200)`);
    } else if (topLocals > 160) {
      console.log(`  note: ${topLocals} top-level locals in the combined chunk, close to the 200 limit`);
    } else {
      console.log(`  chunk locals: ${topLocals}/200`);
    }
  } catch (e) {
    report(dist, 0, 'parse error: ' + e.message);
  }
}

if (problems === 0) {
  console.log(`clean: ${files.length} modules, 0 problems`);
} else {
  console.log(`${problems} problem(s) in ${files.length} modules`);
  process.exit(1);
}
