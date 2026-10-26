'use strict';
const assert = require('node:assert/strict');
const {assertTarget} = require('../scripts/deploy_netlify.cjs');
assertTarget({id: 'expected-site-id', name: 'stalwart-travesseiro-1e8045'});
assert.throws(() => assertTarget({id: 'wrong-site-id', name: 'pointage-tcz-test'}), /Target mismatch/);
assert.throws(() => assertTarget({name: 'stalwart-travesseiro-1e8045'}), /Target mismatch/);
assert.throws(() => assertTarget({id: 'expected-site-id', name: 'stalwart-travesseiro-1e8045-copy'}), /Target mismatch/);
console.log('PASS: exact Netlify target required; alternate site, similarly named site and missing ID rejected');
