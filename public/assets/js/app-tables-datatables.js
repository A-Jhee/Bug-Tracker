/*!
 * Your-project-name v1.0.0
 * http://project-homepage.com
 *
 * Copyright (c) 2021 Your Company
 */

var App = (function () {
  'use strict';

  App.dataTables = function( ){

    //We use this to apply style to certain elements
    $.extend( true, $.fn.dataTable.defaults, {
      dom:
        "<'row mai-datatable-header'<'col-sm-6'l><'col-sm-6'f>>" +
        "<'row mai-datatable-body'<'col-sm-12'tr>>" +
        "<'row mai-datatable-footer'<'col-sm-5'i><'col-sm-7'p>>"
    } );

    $.extend( $.fn.dataTable.ext.classes, {
      sFilterInput:  "form-control form-control-sm",
      sLengthSelect: "form-control form-control-sm",
    } );

    $("#table-unresolved").dataTable({
      "order": [[ 7, "desc" ]]
    });
    $("#table-resolved").dataTable({
      "order": [[ 7, "desc" ]]
    });
    $("#table-submission").dataTable({
      "order": [[ 7, "desc" ]]
    });
    $("#table-project-tickets").dataTable({
      "order": [[ 7, "desc" ]]
    });

    $("#table1").dataTable({
    });
    $("#table2").dataTable({
    });
    $("#table3").dataTable({
    });
  };

  return App;
})(App || {});
