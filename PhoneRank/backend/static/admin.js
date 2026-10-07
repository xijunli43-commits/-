'use strict';
const $ = s => document.querySelector(s);
let state, view = 'phones', editing, editorMode = 'form', reviewing, timer;
const labels = {name:'名称',id:'ID',brand:'品牌',platform:'平台',rank:'原榜名次',releaseDate:'发布时间',soc:'芯片',antutu:'安兔兔成绩',geekbench:'Geekbench',body:'机身',display:'屏幕',camera:'相机',battery:'电池',audio:'音频',haptics:'触感',features:'功能特性',sources:'来源',notes:'备注',cpu:'CPU',gpu:'GPU',total:'总分',single:'单核',multi:'多核',period:'统计期间',capacity:'容量',weight:'重量',vendor:'厂商',category:'芯片类别',status:'发布状态',process:'工艺',memory:'内存',npu:'NPU',cache:'缓存',appliesTo:'适用设备',devices:'代表设备'};
const json = v => JSON.stringify(v, null, 2);
function el(tag, text, cls) { const n = document.createElement(tag); if(text !== undefined)n.textContent=text; if(cls)n.className=cls; return n; }
function message(text) { $('#status').textContent=text; clearTimeout(timer); timer=setTimeout(()=>$('#status').textContent='',8000); }
async function api(path, payload) {
  const options=payload===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':state.csrf},body:JSON.stringify(payload)};
  const response=await fetch(path,options); const data=await response.json();
  if(!response.ok)throw new Error(data.error||'请求失败'); return data;
}
async function refresh() {
  state=await api('/admin/api/state');
  const c=state.catalog, pending=state.candidates.filter(c=>c.status==='pending').length;
  $('#phoneCount').textContent=c.phones.length; $('#chipCount').textContent=c.chips.length; $('#pendingCount').textContent=pending;
  $('#statPhones').textContent=c.phones.length; $('#statChips').textContent=c.chips.length; $('#statPending').textContent=pending;
  $('#publishedAt').textContent=state.publishedAt.slice(0,10); render();
}
function changeView(next) {
  view=next; $('#search').value='';
  const isChip=view==='chips', select=$('#platform'); select.replaceChildren();
  const choices=isChip?[['all','全部类别'],['phone','手机 SoC'],['apple-a','Apple A'],['apple-m','Apple M'],['other','其他']]:[['all','全部平台'],['android','Android'],['ios','iOS']];
  for(const [value,title] of choices){const opt=el('option',title);opt.value=value;select.append(opt);}
  render();
}
function render() {
  document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.view===view));
  $('#pageTitle').textContent={phones:'手机资料',chips:'芯片资料',imports:'采集与审核',history:'修改历史'}[view];
  $('#recordsPanel').hidden=!['phones','chips'].includes(view); $('#importsPanel').hidden=view!=='imports'; $('#historyPanel').hidden=view!=='history';
  if(view==='imports')renderCandidates(); else if(view==='history')renderHistory(); else renderRecords();
}
function renderRecords() {
  const q=$('#search').value.trim().toLowerCase(), platform=$('#platform').value;
  const records=state.catalog[view].filter(d=>(platform==='all'||(view==='phones'?d.platform:d.category)===platform)&&[d.name,d.brand,d.vendor,d.soc?.name,d.soc?.alias].join(' ').toLowerCase().includes(q));
  const body=$('#records'); body.replaceChildren();
  for(const d of records){
    const tr=el('tr'), name=el('td'); name.append(el('b',d.name),el('small',d.soc?.name||d.process||'未查证'));
    tr.append(name,el('td',d.brand||d.vendor||'—'),el('td',d.platform||d.category||'—'),el('td',d.antutu?.total?.toLocaleString()||'未查证'));
    const gb=d.geekbench?.gb6||d.gb6; tr.append(el('td',gb?.single!=null?`${gb.single.toLocaleString()} / ${gb.multi?.toLocaleString()||'未查证'}`:'未查证'));
    const action=el('td'), edit=el('button','编辑','edit');edit.addEventListener('click',()=>openEditor(d.id).catch(e=>message(e.message)));action.append(edit);tr.append(action);body.append(tr);
  }
  $('#empty').hidden=records.length>0; $('#recordCount').textContent=`显示 ${records.length} 条 · 手动编辑和导入均先保存为草稿`;
}
function formFields(data) {
  const root=$('#fieldEditor');root.replaceChildren();
  function add(parent,key,value,path) {
    if(value!==null&&typeof value==='object'&&!Array.isArray(value)){
      const fs=el('fieldset');fs.append(el('legend',labels[key]||key)); for(const [k,v]of Object.entries(value))add(fs,k,v,[...path,k]);parent.append(fs);return;
    }
    const label=el('label',labels[key]||key), input=el(Array.isArray(value)?'textarea':typeof value==='boolean'?'select':'input');
    input.dataset.path=JSON.stringify(path);input.dataset.type=Array.isArray(value)?'json':typeof value==='boolean'?'boolean':typeof value==='number'?'number':value===null?'null':'string';
    if(typeof value==='boolean'){for(const v of ['true','false']){const o=el('option',v==='true'?'支持':'不支持');o.value=v;input.append(o);}}
    input.value=Array.isArray(value)?json(value):value===null?'':String(value);
    if(path.length===1&&key==='id'&&editing.version>0)input.readOnly=true;
    if(input.tagName==='TEXTAREA')input.rows=4;
    label.append(input);parent.append(label);
  }
  for(const [key,value] of Object.entries(data)){const fs=el('fieldset');fs.append(el('legend',labels[key]||key));if(value!==null&&typeof value==='object'&&!Array.isArray(value)){for(const [k,v]of Object.entries(value))add(fs,k,v,[key,k]);}else add(fs,key,value,[key]);root.append(fs);}
}
function readFields() {
  const data=structuredClone(editing.data);
  for(const input of $('#fieldEditor').querySelectorAll('[data-path]')){
    const path=JSON.parse(input.dataset.path),type=input.dataset.type;let value=input.value;
    if(type==='json'){value=JSON.parse(value);if(!Array.isArray(value))throw new Error('数组字段需保持 JSON 数组。');}
    else if(type==='boolean')value=value==='true';
    else if(type==='number'||type==='null'){
      if(value==='')value=null;else if(type==='number'||/^(single|multi|cpu|gpu|total|mem|ux|rank|capacity|height|width|thickness|weight|size|ppi|refresh|wired|wireless|samples|freqGHz|bandwidthGBs|maxGB)$/.test(path.at(-1))){value=Number(value);if(!Number.isFinite(value))throw new Error('数值字段格式错误。');}
    }
    let node=data;for(const key of path.slice(0,-1))node=node[key];node[path.at(-1)]=value;
  }return data;
}
function setEditorMode(mode) {
  try{if(mode===editorMode)return;if(mode==='json')$('#jsonEditor').value=json(readFields());else{editing.data=JSON.parse($('#jsonEditor').value);formFields(editing.data);}editorMode=mode;$('#fieldEditor').hidden=mode!=='form';$('#jsonEditor').hidden=mode!=='json';$('#formMode').classList.toggle('active',mode==='form');$('#jsonMode').classList.toggle('active',mode==='json');}catch(e){$('#editorError').textContent=e.message;}
}
async function openEditor(id) {
  const kind=view;
  if(id!==undefined)editing={...(await api(`/admin/api/records/${kind}/${encodeURIComponent(id)}`)),kind};
  else editing={kind,version:0,data:kind==='phones'?{id:crypto.randomUUID(),name:'新手机',brand:'',platform:'android',soc:{name:'',alias:''},antutu:{total:null,cpu:null,gpu:null,mem:null,ux:null,period:'',source:''},geekbench:{gb6:{single:null,multi:null,source:null},gb7:{single:null,multi:null,source:null}},body:{weight:null},display:{size:null,refresh:null},battery:{capacity:null,wired:null,wireless:null},sources:[],notes:''}:{id:crypto.randomUUID(),name:'新芯片',vendor:'',category:'phone',status:'未查证',process:'',antutu:{total:null,cpu:null,gpu:null},gb6:{single:null,multi:null,samples:0,sources:[]},gb7:{single:null,multi:null,samples:0,sources:[]},sources:[],notes:''}};
  editorMode='form';$('#fieldEditor').hidden=false;$('#jsonEditor').hidden=true;$('#formMode').classList.add('active');$('#jsonMode').classList.remove('active');
  $('#editorTitle').textContent=editing.version?'编辑 · '+editing.data.name:'新建资料';$('#editorError').textContent='';$('#deleteRecord').hidden=!editing.version;formFields(editing.data);$('#jsonEditor').value=json(editing.data);$('#editor').showModal();
}
function renderCandidates() {
  const box=$('#candidates');box.replaceChildren();const pending=state.candidates.filter(c=>c.status==='pending');
  if(!pending.length)box.append(el('p','没有待审核项。抓取或导入公开页面后，候选成绩会出现在这里。','surface'));
  for(const c of pending){const card=el('div',undefined,'candidate surface'),text=el('div');text.append(el('span',c.data.source==='antutu'?'安兔兔':'Geekbench','badge'),el('h3',c.data.name),el('p',c.data.note,'helper'));const review=el('button','审核匹配','secondary');review.addEventListener('click',()=>openReview(c).catch(e=>message(e.message)));const reject=el('button','忽略','danger');reject.addEventListener('click',async()=>{try{await api('/admin/api/reject',{id:c.id});await refresh();}catch(e){message(e.message);}});card.append(text,review,reject);box.append(card);}
}
async function openReview(candidate) {
  reviewing=candidate;$('#reviewNote').textContent=candidate.data.name+' · '+candidate.data.note;$('#targetKind').value=candidate.data.kind;$('#reviewError').textContent='';fillTargets();$('#review').showModal();await updateDiff();
}
function fillTargets() {
  const select=$('#targetRecord'),kind=$('#targetKind').value;select.replaceChildren();
  const blank=el('option','请选择匹配资料');blank.value='';select.append(blank);
  for(const d of state.catalog[kind]){const option=el('option',d.name+(d.ram?' · '+d.ram+'/'+d.storage:''));option.value=String(d.id);select.append(option);}
  const match=state.catalog[kind].find(d=>d.name.replace(/\s/g,'').toLowerCase()===reviewing.data.name.replace(/\s/g,'').toLowerCase());if(match)select.value=String(match.id);
}
async function updateDiff() {
  let patch=structuredClone(reviewing.data.patch),kind=$('#targetKind').value;
  if(kind==='chips'&&patch.geekbench)patch=patch.geekbench;
  $('#afterPatch').textContent=json(patch);const id=$('#targetRecord').value;
  if(!id){$('#beforePatch').textContent='选择目标后显示';return;}
  try{const old=await api(`/admin/api/records/${kind}/${encodeURIComponent(id)}`);reviewing.target=old;reviewing.targetID=id;reviewing.targetKind=kind;$('#beforePatch').textContent=json(Object.fromEntries(Object.keys(patch).map(k=>[k,old.data[k]??null])));}catch(e){$('#reviewError').textContent=e.message;}
}
function renderHistory(){const root=$('#history');root.replaceChildren();for(const h of state.history){const row=el('div',undefined,'history-row');row.append(el('span',`${h.action} · ${h.kind||'发布'} ${h.record_id||''}`),el('small',new Date(h.at).toLocaleString()));if(['save','delete'].includes(h.action)){const button=el('button','恢复旧值','secondary');button.addEventListener('click',async()=>{if(!confirm('将此记录的旧值恢复到草稿？'))return;try{await api('/admin/api/restore',{audit_id:h.id});await refresh();message('旧值已恢复为草稿。');}catch(e){message(e.message);}});row.append(button);}root.append(row);}if(!state.history.length)root.append(el('p','尚无修改记录。'));}
document.querySelectorAll('nav button').forEach(b=>b.addEventListener('click',()=>changeView(b.dataset.view)));
document.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',()=>$('#'+b.dataset.close).close()));
$('#search').addEventListener('input',renderRecords);$('#platform').addEventListener('change',renderRecords);
$('#newRecord').addEventListener('click',()=>openEditor().catch(e=>message(e.message)));
$('#formMode').addEventListener('click',()=>setEditorMode('form'));$('#jsonMode').addEventListener('click',()=>setEditorMode('json'));
$('#editorForm').addEventListener('submit',async event=>{event.preventDefault();try{const data=editorMode==='json'?JSON.parse($('#jsonEditor').value):readFields();if(editing.version&&String(data.id)!==String(editing.data.id))throw new Error('不能更改已有资料的 ID。');await api('/admin/api/save',{kind:editing.kind,data,version:editing.version});$('#editor').close();await refresh();message('草稿已保存，发布后应用才会更新。');}catch(e){$('#editorError').textContent=e.message;}});
$('#deleteRecord').addEventListener('click',async()=>{if(!confirm('删除此资料草稿？历史记录会保留，发布后才影响应用。'))return;try{await api('/admin/api/delete',{kind:editing.kind,id:editing.data.id,version:editing.version});$('#editor').close();await refresh();message('已从草稿删除。');}catch(e){$('#editorError').textContent=e.message;}});
$('#publish').addEventListener('click',async()=>{if(!confirm('将当前全部草稿发布给应用？已有发布版本会保存为快照。'))return;try{await api('/admin/api/publish',{});await refresh();message('发布成功。应用可获取最新数据。');}catch(e){message(e.message);}});
$('#source').addEventListener('change',()=>{$('#sourceURL').value=$('#source').value==='antutu'?'https://www.antutu.com/ranking':'';});
$('#htmlFile').addEventListener('change',async()=>{const file=$('#htmlFile').files[0];if(file){if(file.size>2000000){message('HTML 文件需小于 2 MB。');return;}$('#sourceHTML').value=await file.text();}});
$('#collect').addEventListener('click',async()=>{const button=$('#collect');button.disabled=true;button.textContent='采集中…';try{const result=await api('/admin/api/collect',{source:$('#source').value,url:$('#sourceURL').value,html:$('#sourceHTML').value||null});await refresh();message(`已创建 ${result.candidates.length} 个待审核项。`);}catch(e){message(e.message);}finally{button.disabled=false;button.textContent='采集到待审核区';}});
$('#refreshImports').addEventListener('click',()=>refresh().catch(e=>message(e.message)));
$('#targetKind').addEventListener('change',()=>{fillTargets();updateDiff();});$('#targetRecord').addEventListener('change',updateDiff);
$('#applyCandidate').addEventListener('click',async()=>{const kind=$('#targetKind').value,id=$('#targetRecord').value;try{if(!id||reviewing.targetID!==id||reviewing.targetKind!==kind)throw new Error('请先选择目标并等待当前成绩加载。');await api('/admin/api/apply',{candidate_id:reviewing.id,kind,target_id:id,version:reviewing.target.version});$('#review').close();await refresh();message('成绩已应用到草稿。');}catch(e){$('#reviewError').textContent=e.message;}});
refresh().catch(e=>message(e.message));
