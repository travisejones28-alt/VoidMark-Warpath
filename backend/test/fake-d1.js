// A small in-memory stand-in for Cloudflare D1, built on Node's own SQLite (node:sqlite),
// so the Worker can be tested without any extra packages.
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';

class Statement {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Statement(this.db, this.sql, args.map((a) => (a === undefined ? null : a)));
  }
  _stmt() {
    return this.db.prepare(this.sql);
  }
  async first() {
    const r = this._stmt().get(...this.args);
    return r ? { ...r } : null;
  }
  async all() {
    return { results: this._stmt().all(...this.args).map((r) => ({ ...r })), success: true };
  }
  async run() {
    const r = this._stmt().run(...this.args);
    return { success: true, meta: { changes: Number(r.changes) } };
  }
  _runSync() {
    const r = this._stmt().run(...this.args);
    return { success: true, meta: { changes: Number(r.changes) } };
  }
}

export class FakeD1 {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    const schema = readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8');
    this.db.exec(schema);
  }
  prepare(sql) {
    return new Statement(this.db, sql);
  }
  async batch(stmts) {
    this.db.exec('BEGIN');
    try {
      const out = stmts.map((s) => s._runSync());
      this.db.exec('COMMIT');
      return out;
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }
  count(table, where = '1=1', ...args) {
    return Number(this.db.prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE ${where}`).get(...args).c);
  }
}
