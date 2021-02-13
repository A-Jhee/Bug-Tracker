function makeDayLabel(date) {
  return date.toDateString().split(' ')[1].concat(' ', date.toDateString().split(' ')[2]);
};

function nextDate(date) {
  return new Date(date.setDate(date.getDate() + 1));
};

function twoWeeksDate() {
  // starting date is two weeks ago from today.
  var startDate = new Date(Date.now() - 12096e5);
  var result = [];
  for (let days = 0; days < 14; days += 1) {
    result.push(nextDate(startDate));
  };

  return result;
};

function xAxisLabels(twoWeeksArray) {
  return twoWeeksArray.map(date => makeDayLabel(date));
};

function queryDates(twoWeeksArray) {
  return twoWeeksArray.map(date => date.toISOString().substring(0,10));
};

const dotenv = require('dotenv');
dotenv.config();

const { Pool, Client } = require('pg');
const pool = new Pool();

(async () => {
  var allCounts = {}
  var sqlOpen = "SELECT date(created_on), count(id) FROM tickets WHERE created_on::date = $1 AND status = 'Open' GROUP BY created_on;";
  var sqlResolved = "SELECT date(updated_on), count(id) FROM tickets WHERE updated_on::date = $1 AND status = 'Resolved' GROUP BY updated_on;";
  var datesParams = queryDates(twoWeeksDate());

  async function countTickets (dates) {
    await dates.reduce(async (promise, date) => {
      await promise;
      const queryOpenResult = await pool.query(sqlOpen, [date]);
      if (queryOpenResult.rows[0]) {
        allCounts[date] = { Open: queryOpenResult.rows[0]['count'] };
      } else {
        allCounts[date] = { Open: '0' };
      }
      const queryResolvedResult = await pool.query(sqlResolved, [date]);
      if (queryResolvedResult.rows[0]) {
        allCounts[date]['Resolved'] = queryResolvedResult.rows[0]['count'];
      } else {
        allCounts[date]['Resolved'] = '0' ;
      }
    }, Promise.resolve());
  }

  await countTickets(datesParams);
  // console.log(allCounts);
  await pool.end();

  openTicketCounts = [];
  resolvedTicketCounts = [];
  for (const date of datesParams) {
    openTicketCounts.push(allCounts[date]['Open']);
    resolvedTicketCounts.push(allCounts[date]['Resolved']);
  }
  console.log(openTicketCounts);
  console.log(resolvedTicketCounts);
})();