const fs = require('fs');
const path = require('path');
const packageRoot = process.env.ER_DEPENDENCY_PACKAGES || 'C:/Users/liyehao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const { instance } = require(path.join(packageRoot, '@viz-js/viz/dist/viz.cjs'));
const sharp = require(path.join(packageRoot, 'sharp'));
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'docs/第二周关系模式与数据字典.md'), 'utf8');
const tables = [];
// Read each schema section by heading boundaries; never use deferred sample tuples.
const headings = [...source.matchAll(/^### 3\.\d+ (\w+) (.+)$/gm)];
const uniqueFields = {Member: ['phone'], AddOn: ['addon_name']};
const notes = {
  Employee: 'salary：元／月\nrole：店员／店长',
  DutyRoster: 'UK(employee_id, start_time)\nstart_time < end_time',
  SalesOrder: 'member_id 可空；不存单一员工外键',
  Specification: '温度／糖度／杯型\nUK(spec_type, spec_name)\nUK(spec_id, spec_type)\n后者供复合外键引用',
  ProductSpecification: '商品可选规格＋每杯加价',
  SpecificationIngredient: '仅系数调整\n同原料多规格系数相乘',
  ItemSpec: '每种类型最多一个；共最多三种\n复合 FK(spec_id, spec_type)',
  OrderItem: 'unit_price 含规格加价和加料\nsub_amount =\nunit_price × quantity',
  OrderItemIngredient: 'amount 为全部杯数的实际扣减量',
  AddOn: '一种加料对应一种原料\nprice／extra_amount 按一份\n库存存放在 Ingredient',
  ItemAddOn: '每杯同一种加料最多一份\n总份数 = OrderItem.quantity\n不另设加料数量字段'
};
const groups = {
  staff: ['Employee', 'DutyRoster'],
  catalog: ['Product', 'Recipe', 'Ingredient', 'Specification', 'ProductSpecification', 'SpecificationIngredient', 'AddOn'],
  sales: ['Member', 'SalesOrder', 'OrderItem', 'ItemSpec', 'ItemAddOn', 'OrderItemIngredient']
};
const groupStyles = {
  staff: ['员工与值班', '#f0fdfa', '#0f766e'],
  catalog: ['商品、配方与可选配置', '#f6f5ff', '#6d28d9'],
  sales: ['订单与实际选择', '#eff6ff', '#1d4ed8']
};
for (let i=0;i<headings.length;i++) {
  const h = headings[i];
  const end = i+1<headings.length ? headings[i+1].index : source.indexOf('## 4 样例元组', h.index);
  const body = source.slice(h.index+h[0].length, end);
  const rows = body.split('\n').filter(line=>line.startsWith('|')).slice(2).map(line=>line.split('|').slice(1,-1).map(x=>x.trim()));
  const fields = rows.map(r=>({name:r[0],nullable:r[2]==='是',key:[r[4].includes('PK')?'PK':'',r[4].includes('FK')||(h[1]==='ItemSpec'&&r[0]==='spec_type')?'FK':'',uniqueFields[h[1]]?.includes(r[0])?'UK':''].filter(Boolean).join('/')}));
  tables.push({name:h[1],title:h[2],fields});
}
if(tables.length!==15) throw new Error('Expected 15 schema tables, got '+tables.length);
const q = s => JSON.stringify(s);
const esc = s => s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
function wrapNotes(value, limit=28) {
 return value.split('\n').map(line=>{
  const lines=[];let current='',width=0;
  for(const char of line) {
   const delta=char.charCodeAt(0)>255?2:1;
   if(width+delta>limit){lines.push(current);current='';width=0;}
   current+=char;width+=delta;
  }
  if(current)lines.push(current);
  return lines.join('\n');
 }).join('\n');
}
// parent, child, parent cardinality per child, children per parent, optional label
const relations = [
 ['Member','SalesOrder','0..1','0..N','会员可选'],
 ['Employee','DutyRoster','1','0..N',''],
 ['SalesOrder','OrderItem','1','1..N',''],
 ['Product','OrderItem','1','0..N',''],
 ['Product','Recipe','1','0..N',''],
 ['Ingredient','Recipe','1','0..N',''],
 ['Product','ProductSpecification','1','0..N',''],
 ['Specification','ProductSpecification','1','0..N',''],
 ['ProductSpecification','SpecificationIngredient','1','0..N','复合外键'],
 ['Ingredient','SpecificationIngredient','1','0..N',''],
 ['Ingredient','AddOn','1','0..N',''],
 ['OrderItem','ItemSpec','1','0..3',''],
 ['Specification','ItemSpec','1','0..N','复合外键'],
 ['OrderItem','ItemAddOn','1','0..N',''],
 ['AddOn','ItemAddOn','1','0..N',''],
 ['OrderItem','OrderItemIngredient','1','1..N',''],
 ['Ingredient','OrderItemIngredient','1','0..N','']
];
let dot = `digraph ER {\ngraph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0, pad=0.28, bgcolor="white", fontname="Microsoft YaHei"];\nnode [shape=box, style="rounded,filled", fontname="Microsoft YaHei", fontsize=12, margin="0.18,0.14"];\nedge [fontname="Microsoft YaHei", fontsize=10, color="#64748b", fontcolor="#475569", penwidth=1.15, dir=none, labeldistance=1.7, labelangle=24];\n`;
for(const [key,names] of Object.entries(groups)) {
 const [title,background,color] = groupStyles[key];
 for(const name of names) {
   const t=tables.find(t=>t.name===name);
   const fieldText=t.fields.map(f=>(f.key?f.key+'  ':'')+f.name+(f.nullable?' ?':'')).join('\n');
   const textLabel=t.title+'\n'+name+'\n────────────────────\n'+fieldText+(notes[name]?'\n────────────────────\n'+wrapNotes(notes[name]):'');
   dot+=`${name} [label=${q(textLabel)}, fillcolor=${q(background)}, color=${q(color)}, fontcolor="#0f172a"];\n`;
 }
}
for(const [p,c,a,b,label] of relations) dot+=`${p} -> ${c} [taillabel=${q(a)}, headlabel=${q(b)}, label=${q(label)}];\n`;
dot+='SalesOrder -> DutyRoster [style=dashed, color="#c2410c", fontcolor="#9a3412", penwidth=1.8, constraint=false, label="按订单时间匹配 M:N\\n非外键关系"];\n}\n';
async function main() {
 console.log('Schema parsed. Initializing diagram renderer.');
 const viz=await instance();
 console.log('Rendering graph layout.');
 const dir=path.join(root,'docs/er');fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(dir,'ER图_修订版.dot'),dot);
 const svg=viz.renderString(dot,{format:'svg',engine:'dot'});
 const viewBox=svg.match(/viewBox="([\d.\s-]+)"/)[1].split(/\s+/).map(Number);
 const w=viewBox[2],h=viewBox[3];
 const start=svg.indexOf('>',svg.indexOf('<svg'))+1;
 const body=svg.slice(start,svg.lastIndexOf('</svg>'));
 const top=142,bottom=150,side=35;
 const width=w+2*side,height=h+top+bottom;
 const text=(x,y,size,str,color='#0f172a',weight='normal')=>`<text x="${x}" y="${y}" font-family="Microsoft YaHei" font-size="${size}" fill="${color}" font-weight="${weight}">${esc(str)}</text>`;
 const header=text(35,40,28,'蜜雪冰城单门店数据库 ER 图',' #0f172a'.trim(),'bold')+text(35,72,15,'修订版 · 2026-10-04 · 15 张表 · 加料结构已确认')+text(35,100,13,'PK 主键（同表多项 PK 表示联合主键）　FK 外键　UK 唯一约束　? 可空　实线：主外键联系　橙色虚线：时间匹配', '#475569')+text(35,124,13,'线端 1 / 0..1 / 0..N / 1..N 表示对应端基数；具体选项和数值待审查，样例数据未纳入本图。','#475569');
 const foot=text(35,h+top+30,14,'值班团队：start_time ≤ order_time < end_time；一笔订单可对应多名员工，订单不保存 employee_id。')+text(35,h+top+57,14,'规格：温度／糖度／杯型；可选配置与实际选择分开；原料规则只做系数调整，同原料多规格系数相乘。')+text(35,h+top+84,14,'价格：基础价＋规格加价快照＋加料价格快照；退款依据实际扣减快照，避免当前配方修改影响历史订单。')+text(35,h+top+111,12,'业务要求订单至少一条明细、实际消耗至少一条；上限及跨表规则仍需流程验证。ItemSpec 的商品适用性由 ProductSpecification 核对。','#64748b');
 const final=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><rect width="100%" height="100%" fill="white"/>${header}<g transform="translate(${side},${top})">${body}</g>${foot}</svg>`;
 fs.writeFileSync(path.join(dir,'ER图_修订版.dot'),dot);
 fs.writeFileSync(path.join(dir,'ER图_修订版.svg'),final);
 console.log('SVG saved. Rendering PNG.');
 await sharp(Buffer.from(final),{density:160,limitInputPixels:false}).png().toFile(path.join(root,'ER图_修订版.png'));
 await sharp(Buffer.from(final),{density:80,limitInputPixels:false}).resize({width:1800}).png().toFile(path.join(dir,'ER图_预览.png'));
 fs.writeFileSync(path.join(dir,'schema.json'),JSON.stringify({tables,relations,derivedRelation:{from:'SalesOrder',to:'DutyRoster',condition:'start_time <= order_time < end_time'}},null,2));
 console.log(JSON.stringify({tables:tables.length,foreignKeyRelations:relations.length,viewBox:[width,height],png:path.join(root,'ER图_修订版.png')},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
