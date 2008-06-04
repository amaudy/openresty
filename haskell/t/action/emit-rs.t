#!/usr/bin/env perl
# vi:filetype=

use strict;
use warnings;

use IPC::Run3;
use Test::Base 'no_plan';
#use Test::LongString;

run {
    my $block = shift;
    my $desc = $block->description;
    my ($stdout, $stderr);
    my $stdin = $block->in;
    run3 [qw< bin/restyaction ast rs >], \$stdin, \$stdout, \$stderr;
    is $? >> 8, 0, "compiler returns 0 - $desc";
    warn $stderr if $stderr;
    my @ln = split /\n+/, $stdout;
    my $ast = $block->ast;
    if (defined $ast) {
        $ln[0] =~ s/"RestyAction" \(line (\d+), column (\d+)\)/($1,$2)/gs;
        is "$ln[0]\n", $ast, "AST ok - $desc";
    }
    shift @ln;
    my $real_out = join "\n", @ln;
    $real_out =~ s/\s+$//smg;
    my $out = $block->out;
    is "$real_out\n", $out, "RestyScript output ok - $desc";
};

__DATA__

=== TEST 1: basic delete
--- in
delete from Foo where id > 3;
--- ast
Action [Delete (Model (Symbol "Foo")) (Where (Compare ">" (Column (Symbol "id")) (Integer 3)))]
--- out
delete from "Foo" where "id" > 3



=== TEST 2: basic update
--- in
update Foo set foo=foo+1
--- ast
Action [Update (Model (Symbol "Foo")) (Assign (Column (Symbol "foo")) (Arith "+" (Column (Symbol "foo")) (Integer 1))) Null]
--- out
update "Foo" set "foo" = ("foo" + 1)



=== TEST 3: update with delete
--- in
update
    Foo set foo = 5 where $col>5 and name like '%hey' ;
    ;
delete from Blah where $col=5
 ;
--- out
update "Foo" set "foo" = 5 where ($col > 5 and "name" like '%hey');
delete from "Blah" where $col = 5



=== TEST 4: simple GET
--- in
GET '/=/version';
--- ast
Action [HttpCmd "GET" (String "/=/version") Null]
--- out
GET '/=/version'



=== TEST 5: GET with expr
--- in
GET ( '/=/'||'ver') || 'sion'
--- ast
Action [HttpCmd "GET" (Arith "||" (Arith "||" (String "/=/") (String "ver")) (String "sion")) Null]
--- out
GET (('/=/' || 'ver') || 'sion')



=== TEST 6: simple POST
--- in
POST '/=/model/Post/~/~'
{ "author": "hello" }
--- ast
Action [HttpCmd "POST" (String "/=/model/Post/~/~") (Object [Pair (String "author") (String "hello")])]
--- out
POST '/=/model/Post/~/~' {'author': 'hello'}



=== TEST 7: POST an empty array
--- in
POST "/=/model/Post/~/~"[]
--- ast
Action [HttpCmd "POST" (String "/=/model/Post/~/~") (Array [])]
--- out
POST '/=/model/Post/~/~' []



=== TEST 8: POST an simple array
--- in
POST
'/=/model/Post/' || '~/~'
[1,2.5,"hi"||'hey']
--- ast
Action [HttpCmd "POST" (Arith "||" (String "/=/model/Post/") (String "~/~")) (Array [Integer 1,Float 2.5,Arith "||" (String "hi") (String "hey")])]
--- out
POST ('/=/model/Post/' || '~/~') [1, 2.5, ('hi' || 'hey')]



=== TEST 9: PUT a hash of lists of hashes
--- in
POST '/=/model/~'
{ "description": "A simple test",
    "columns": [
        { "name": "name", 'type': 'text'},
        { "name":"created","type":"timestamp (0) with time zone", default: ["now()"] }
    ]
}
--- out
POST '/=/model/~' {'description': 'A simple test', 'columns': [{'name': 'name', 'type': 'text'}, {'name': 'created', 'type': 'timestamp (0) with time zone', 'default': ['now()']}]}



=== TEST 10: with variables
--- in
            update Post
            set comments = comments + 1
            where id = $post_id;
            POST '/=/model/Comment/~/~'
            { "sender": $sender, "body": $body, "post": $post_id };
--- out
update "Post" set "comments" = ("comments" + 1) where "id" = $post_id;
POST '/=/model/Comment/~/~' {'sender': $sender, 'body': $body, 'post': $post_id}

