# README #

## GECKO bug tracker is an issue tracker for software development teams. ##

[Visit GECKO bug tracker to experience it live!](https://geckobugtracker.herokuapp.com/)

### Under The Hood ###

GECKO bug tracker is built using Ruby on the backend. I used Sinatra, which is a microframework that builds upon Rack middleware.

"bugtracker.rb" in the root directory contains the business logic and serves as the controller.

In the "models" directory are the User, Ticket, and Project class definitions that serve as common collection of data that the app interacts with.

SQL database is used and connect via Ruby's PG gem.

### On The Surface ###

Frontend is built with HTML5 and CSS3 using Bootstrap 4 framework.

Various JavaScript libraries and jQuery plugins are used to bring visual flair and modern UI/UX that today's consumers come to expect.