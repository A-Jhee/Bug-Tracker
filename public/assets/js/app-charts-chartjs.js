// var App = (function () {
// 	'use strict';

// 	App.ChartJs = function(){

//     function makeDayLabel(date) {
//       return date.toDateString().split(' ')[1].concat(' ', date.toDateString().split(' ')[2]);
//     };

//     function nextDate(date) {
//       return new Date(date.setDate(date.getDate() + 1));
//     };

//     function xAxisLabels() {
//       var fortniteAgo = new Date(Date.now() - 12096e5);
//       var result = [];

//       for (let days = 0; days < 14; days += 1) {
//         var date = nextDate(fortniteAgo);
//         result.push(makeDayLabel(date));
//       };
//       return result
//     };

//     var randomScalingFactor = function() {
//       return Math.round(Math.random() * 20);
//     };

// 		function barChart(){
// 			//Set the chart colors
//       var color1 = tinycolor( "#43f6ae" );
// 			var color2 = tinycolor( "#2cc185" );

//       //Get the canvas element
// 			var ctx = document.getElementById("bar-chart");
			
// 			var data = {
// 	      labels: xAxisLabels(),    // X-axis labels (shows last 14 dates)
// 	      datasets: [{
// 	        label: "New Tickets",
// 	        borderColor: color1.toString(),
// 	        backgroundColor: color1.toString(),
// 	        data: [
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor()
//                 ]
// 	      }, {
// 	        label: "Resolved Tickets",
// 	        borderColor: color2.toString(),
// 	        backgroundColor: color2.toString(),
// 	        data: [
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor(),
//                   randomScalingFactor(), randomScalingFactor()
//                 ]
// 	      }]
// 	    };

// 	    var bar = new Chart(ctx, {
//         type: 'bar',
//         data: data,
//         options: {
//           elements: {
//             rectangle: {
//               borderWidth: 2,
//               borderColor: 'rgb(0, 255, 0)',
//               borderSkipped: 'bottom'
//             }
//           },
//         }
//       });
// 		}

// 		barChart();
// 	};

// 	return App;
// })(App || {});




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

// var sqlDatesParams = queryDates(twoWeeksDate());

const dotenv = require('dotenv');
dotenv.config();


const { Pool, Client } = require('pg');
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------

// const pool = new Pool();

// var sqlOpen = "SELECT * FROM tickets WHERE created_on::date = $1 AND status = 'Open';";
// var sqlResolved = "SELECT * FROM tickets WHERE updated_on::date = $1 AND status = 'Resolved';";

// var date = '2021-01-27'

// pool.connect((err, client, release) => {
//   if (err) {
//     return console.error('Error connecting to database.', err.stack);
//   };

//   var sqlOpen = "SELECT * FROM tickets WHERE created_on::date = $1 AND status = 'Open';";
//   var sqlResolved = "SELECT * FROM tickets WHERE updated_on::date = $1 AND status = 'Resolved';";

//   var ticketCounts = { openTickets: [], resolvedTickets: [] };

//   sqlDatesParams.forEach(function(date) {
//     client.query(sqlOpen, [date], (err, result) => {
//       release();
//       if (err) {
//         return console.error('Error executing query.', err.stack);
//       };

//       console.log(result.rows.length);
//     });

//     client.query(sqlResolved, [date], (err, result) => {
//       if (err) {
//         return console.error('Error executing query.', err.stack);
//       };

//       ticketCounts['resolvedTickets'].push(result.rows.length);
//     });
//   });

//   pool.end();
// });
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------

var sqlDatesParams = queryDates(twoWeeksDate());
var sqlOpen = "SELECT count(id) FROM tickets WHERE created_on::date = $1 AND status = 'Open';";
var sqlResolved = "SELECT * FROM tickets WHERE updated_on::date = $1 AND status = 'Resolved';";

var ticketCounts = { openTickets: [], resolvedTickets: [] };

const pool = new Pool();

pool.query(sqlOpen, [sqlDatesParams[0]], (err, res) => {
  if (err) {
    throw err;
  }
  console.log(res.rows[0]['count']);
});

pool.query(sqlOpen, [sqlDatesParams[1]], (err, res) => {
  if (err) {
    throw err;
  }
  console.log(res.rows[0]['count']);
});

pool.query(sqlOpen, [sqlDatesParams[2]], (err, res) => {
  if (err) {
    throw err;
  }
  console.log(res.rows[0]['count']);
});

pool.end();

// const start = async function (date) {
//   const { Pool, Client } = require('pg');

//   const pool = new Pool();

//   var sql = "SELECT * FROM tickets WHERE created_on::date = $1 AND status = 'Open';";
//   var params = [date];
//   pool.query(sql, params, (err, res) => {
//     console.log(err, res['rows']);
//   });

//   var sql2 = "SELECT * FROM tickets WHERE updated_on::date = $1 AND status = 'Resolved';";
//   var params2 = [date];
//   pool.query(sql2, params2, (err, res) => {
//     console.log(err, res['rows']);
//     pool.end();
//   });
// };