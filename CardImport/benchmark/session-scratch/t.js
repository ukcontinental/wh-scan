const {chromium}=require('/opt/node22/lib/node_modules/playwright');
(async()=>{const b=await chromium.launch();const c=await b.newContext({deviceScaleFactor:2,viewport:{width:1050,height:600}});const p=await c.newPage();
await p.setContent('<html><body style="margin:0;font-family:\'Noto Sans CJK TC\'"><div style="font-size:60px">王大明 David 陳約翰 品質第一</div><div style="writing-mode:vertical-rl;font-size:40px;height:400px">台北市信義區</div></body></html>');
await p.screenshot({path:'t.png'});await b.close();console.log('done')})();
