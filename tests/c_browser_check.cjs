/* Optional browser acceptance. Set PLAYWRIGHT_MODULE to an installed package path. */
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');
const output = 'results/phase2/web/2026-11-10-c-pages';
fs.mkdirSync(output, {recursive:true});
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  const context = await browser.newContext({viewport:{width:1365,height:950}});
  const page = await context.newPage();
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  page.on('dialog', d => d.accept());
  const base = 'http://127.0.0.1:5051';
  async function login(name, password) {
    await context.clearCookies();
    await page.goto(base+'/login');
    await page.locator('[name=login_name]').fill(name);
    await page.locator('[name=password]').fill(password);
    await Promise.all([page.waitForURL(url=>!url.pathname.startsWith('/login')),page.getByRole('button',{name:'登录',exact:true}).click()]);
  }
  try {
    await login('guesta','Guest#2026');
    await page.goto(base+'/orders/new');
    if(await page.locator('#checkout-form').evaluate(f=>f.checkValidity())) throw Error('Specs should be required');
    for(const select of await page.locator('.basket-spec').all()) await select.selectOption({index:1});
    const first = await page.locator('#basket-total').textContent();
    await page.locator('.basket-quantity').fill('2');
    const second = await page.locator('#basket-total').textContent();
    if(first===second) throw Error('Price preview did not change');
    await page.getByRole('button',{name:'添加一件商品'}).click();
    for(const select of await page.locator('.basket-spec').all()) await select.selectOption({index:1});
    await page.screenshot({path:output+'/checkout.png',fullPage:true});
    await page.selectOption('#payment','false');
    await Promise.all([page.waitForNavigation(),page.locator('#submit-order').click()]);
    if(!await page.getByRole('alert').count()) throw Error('Payment failure not visible');
    if(await page.locator('.basket-product').count()!==2) throw Error('Basket lost after failure');
    await page.selectOption('#payment','true');
    await Promise.all([page.waitForNavigation(),page.locator('#submit-order').click()]);
    if(!page.url().includes('/my/orders')) throw Error('Checkout did not redirect');
    await login('manager1','Manager#2026');
    await page.goto(base+'/admin/maintenance');
    await page.screenshot({path:output+'/maintenance-center.png',fullPage:true});
    for (const resource of ['products','ingredients','employees','specifications','product-specifications','recipes','specification-ingredients','addons','duty-rosters']) {
      const response=await page.goto(base+'/admin/maintenance/'+resource);
      if(response.status()!==200) throw Error(resource+' render failed');
      if(await page.locator('main').evaluate(el=>el.scrollWidth > window.innerWidth)) throw Error(resource+' overflow');
    }
    await page.goto(base+'/admin/maintenance/products?key=P001');
    if(!await page.locator('[name=product_id]').getAttribute('readonly') && !await page.locator('[name=product_id]').evaluate(e=>e.readOnly)) throw Error('Key not locked');
    await page.locator('[name=base_price]').fill('-1');
    if(await page.locator('main form').first().evaluate(f=>f.checkValidity())) throw Error('Negative price accepted');
    await page.screenshot({path:output+'/maintenance-product.png',fullPage:true});
    await page.goto(base+'/admin/orders');
    await page.screenshot({path:output+'/history.png',fullPage:true});
    await page.locator('main table a').first().click();
    if(!await page.getByText('以下成交记录只读',{exact:false}).count()) throw Error('History detail missing');
    await page.setViewportSize({width:390,height:844});
    await page.goto(base+'/admin/maintenance/products');
    if(await page.evaluate(()=>document.documentElement.scrollWidth > innerWidth)) throw Error('Mobile overflow');
    await page.screenshot({path:output+'/mobile-maintenance.png',fullPage:true});
    await login('membera','Member#2026');
    await page.goto(base+'/my/profile');
    if(!await page.getByText('当前积分',{exact:true}).count()) throw Error('Profile missing');
    if(errors.length) throw Error(errors.join('\n'));
    fs.writeFileSync(output+'/browser.txt','PASS: Edge desktop/mobile, required specs, price preview, two-item payment failure/retry, manager pages, invalid price, history, member profile; zero page errors.\n');
    console.log('Browser acceptance passed');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
