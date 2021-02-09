const dotenv = require('dotenv');
dotenv.config();

const start = async function () {
  const { Pool, Client } = require('pg')

  const pool = new Pool()

  pool.query('SELECT * FROM tickets WHERE id=1;', (err, res) => {
    console.log(err, res)
    pool.end()
  })
}

start();
