use t::OpenAPI;

plan tests => 2 * blocks();

run_tests;

__DATA__

=== TEST 1: Delete existing models
--- request
DELETE /=/model
--- response
{"success":1}



=== TEST 2: Create a model
--- request
POST /=/model/Carrie.js
{
    description: "我的书签",
    columns: [
        { name: "title", label: "标题" },
        { name: "url", label: "网址" }
    ]
}
--- response
{"success":1}



=== TEST 3: check the model list again
--- request
GET /=/model.js
--- response
[{"src":"/=/model/Carrie","name":"Carrie","description":"我的书签"}]



=== TEST 4: insert a record 
--- request
POST /=/model/Carrie/*/*.js
{ title:'hello carrie',url:'http://www.carriezh.cn'}
--- response
{"success":1,"rows_affected":1,"last_row":"/=/model/Carrie/id/1"}


=== TEST 5: read a record according to url
--- request
POST /=/model/Carrie/url/http://www.carriezh.cn.js
--- response
[{"url":"http://www.carriezh.cn/","title":"hello carrie","id":"1"}]
