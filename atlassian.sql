CREATE OR REPLACE package atlassian as 
/* created by A. Tarazanov 2019-02-01*/
--API Basic authorization
auth_header varchar2(256) := 'Basic ***REMOVED***';
auth_login varchar2(32)     := '***REMOVED***';
auth_password varchar2(32)  := '***REMOVED***';
--hosts
crowd       varchar2(256) := 'http://crowd-dc***REMOVED***';
jira        varchar2(256) := 'http://jira***REMOVED***';
bitbucket   varchar2(256) := 'http://git***REMOVED***';
confluence  varchar2(256) := 'http://confluence***REMOVED***';
artifactory varchar2(256) := 'http://artapp***REMOVED***';
--Jira Developers role_id
jiraRoleId  varchar2(32)  := '10090';
--artifactory repos prefixes
type repoarray is varray(6) of varchar2(32);
repoprefix  repoarray     := repoarray('-docker-release','-docker-snapshot','-mvn-release','-mvn-snapshot','-generic');
stashprefix repoarray     := repoarray('-STASH-ADMINS','-STASH-DEVELOPERS','-STASH-USERS');      

--functions
function        rest_post (the_url in varchar2, jdata in varchar2) return pls_integer;
function        rest_put_json (the_url in varchar2, jdata in varchar2) return pls_integer;
function        rest_delete (the_url in varchar2) return pls_integer;
function        rest_get (the_url in varchar2) return pls_integer;
function        rest_put (the_url in varchar2) return pls_integer;
function        json_get (the_url in varchar2) return varchar2;

--procedures
procedure       fixGroupsPermissions;
procedure       checkServers;

--Crowd functions
function        crowdCheckUser (user_name in varchar2) return varchar2; 
function        crowdCheckGroup (group_name in varchar2) return varchar2;
function        crowdAddGroup (group_name in varchar2) return varchar2;
function        crowdDeleteGroup (group_name in varchar2) return varchar2;
function        crowdAdduserToGroup (group_name in varchar2, user_name in varchar2) return varchar2;
function        crowdRemoveUserFromGroup (group_name in varchar2, user_name in varchar2) return varchar2;

--Jira functions
function        jiraIsProjectExist (pr_key in varchar2) return varchar2;
function        jiraCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2;
function        jiraDeleteProject (pr_key in varchar2) return varchar2;
function        jiraSetGroupToProjectRole(pr_key in varchar2) return varchar2;

--Bitbucket functions
function        bitbucketIsProjectExist (pr_key in varchar2) return varchar2;
function        bitbucketCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2;
function        bitbucketCreateRepository (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2;
function        bitbucketDeleteProject (pr_key in varchar2) return varchar2;
function        bitbucketDeleteRepository (pr_key in varchar2) return varchar2;
function        bitbucketAddGroupPermToProject (pr_key in varchar2,stashprefix in varchar2) return varchar2;
function        bitbucketAddGroupPermToRepo (pr_key in varchar2, stashprefix in varchar2) return varchar2;

--Confluence functions
function        confluenceIsSpaceExist (pr_key in varchar2) return varchar2;
function        confluenceCreateSpace (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2;
function        confluenceDeleteSpace (pr_key in varchar2) return varchar2;
function        confluenceAddPermissionToGroup (pr_key in varchar2) return varchar2;

--Artifactory functions
function        artifactoryIsRepoExist(pr_key in varchar2) return varchar2;
function        artifactoryCreateRepository(pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return  varchar2;
function        artifactoryDeleteRepository(repo_name in varchar2) return varchar2;
function        artifactoryCreateGroup(pr_key in varchar2) return varchar2;
function        artifactoryCreatePermission(pr_key in varchar2, prefix in varchar2, t_lead in varchar2) return varchar2;
function        artifactoryDeleteGroup(pr_key in varchar2) return varchar2;
function        artifactoryDeletePermission(repo_name in varchar2) return varchar2;

end atlassian;
/


CREATE OR REPLACE package body         atlassian as

-- HTTP POST request with JSON body
function rest_post (the_url in varchar2, jdata in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_body_charset('UTF-8'); --Catalina cannot read request body in AL32UTF8
  utl_http.set_transfer_timeout(20);
  req := utl_http.begin_request(the_url, 'POST','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'content-type', 'application/json');
  utl_http.set_header(req, 'accept', 'application/json');
  --utl_http.set_header(req, 'authorization', auth_header);
  utl_http.set_header(req, 'content-length', lengthb(jdata)); -- lengthB means Binary lenth
  utl_http.write_raw(req, utl_raw.cast_to_raw(jdata)); -- we will send BODY in raw
  resp := utl_http.get_response(req);
  dbms_output.put_line('post status code is '||resp.status_code);
   utl_http.end_response(resp);
  return resp.status_code;
  exception
  WHEN utl_http.too_many_requests THEN
        utl_http.end_response(resp);
end rest_post;

--HTTP PUT request with JSON body
function rest_put_json (the_url in varchar2, jdata in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_body_charset('UTF-8'); --Catalina cannot read request body in AL32UTF8
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'PUT','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'content-type', 'application/json');
  --utl_http.set_header(req, 'authorization', auth_header);
  utl_http.set_header(req, 'content-length', lengthb(jdata)); -- lengthB means Binary lenth
  utl_http.write_raw(req, utl_raw.cast_to_raw(jdata)); -- we will send BODY in raw  
  resp := utl_http.get_response(req);
  dbms_output.put_line('put status code is '||resp.status_code);
  utl_http.end_response(resp);
  return resp.status_code;
  exception WHEN others THEN return '-200';
end rest_put_json;

--HTTP DELETE request
function rest_delete (the_url in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_transfer_timeout(20);
  req := utl_http.begin_request(the_url, 'DELETE','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'user-agent', 'utl_http');
  --utl_http.set_header(req, 'authorization', auth_header);
  resp := utl_http.get_response(req);
  dbms_output.put_line(resp.status_code);
  utl_http.end_response(resp);
  return resp.status_code;
  exception WHEN others THEN return '-200';
end rest_delete;

-- HTTP GET request
function rest_get (the_url in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'GET','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'User-Agent', 'utl_http');
  utl_http.set_header(req, 'accept', 'application/json');
  resp := utl_http.get_response(req);
  utl_http.end_response(resp);  
    return resp.status_code;
  exception WHEN others THEN return '-200';
end rest_get;

-- HTTP PUT request
function rest_put (the_url in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'PUT','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'accept', 'application/json');
  --utl_http.set_header(req, 'authorization', auth_header);
  resp := utl_http.get_response(req);
  utl_http.end_response(resp);
  dbms_output.put_line('put status is '||resp.status_code);
  return resp.status_code;
  exception WHEN others THEN return '-200';
end rest_put;

-- HTTP GET request and parse result
function        json_get (the_url in varchar2) return varchar2
is
  req   utl_http.req;
  resp  utl_http.resp;

BEGIN
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'GET','HTTP/1.1');
  utl_http.set_authentication(req, auth_login, auth_password);
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'accept', 'application/json');
 -- utl_http.set_header(req, 'authorization', auth_header);
  resp := utl_http.get_response(req);
  dbms_output.put_line(resp.status_code);
  utl_http.end_response(resp);
  return resp.status_code;
  exception WHEN others THEN return '-200';
end json_get;

--BMSP-12824 Bitbucket/Confluence/Jira sync trick
procedure       fixGroupsPermissions
is
  url varchar2(512);
  res varchar2(1024);
  group_key varchar2(128);
begin

begin --bitbucket
  for wrec in (
  select full_url, method 
  from atlassian_callrest_result 
  where system_name = 'bitbucket' and method in ('bitbucketAddGroupPermToProject','bitbucketAddGroupPermToRepo') and result_text = 'FAILED')
    loop
    dbms_output.put_line(wrec.full_url);
    res := rest_put(wrec.full_url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 204 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 204 then 'The requested permission was granted'
                           when 400 then 'The request was malformed or the specified permission does not exist.'
                           when 401 then 'The currently authenticated user is not an administrator for the specified project.'
                           when 403 then 'The action was disallowed as it would reduce the currently authenticated users permission level.'
                           when 404 then 'The specified project/repo/group does not exist.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    update atlassian_callrest_result 
    set result_code = json_value(res, '$.response'),
        result_text = json_value(res, '$.result'),
        result_msg = res,
        date_call = sysdate
    where   system_name = 'bitbucket' and method = wrec.method
            and full_url = wrec.full_url;
    end loop;
end;--bitbucket
begin --confluence
for wrec in (select full_url,jdata from atlassian_callrest_result where system_name = 'confluence' and method = 'confluenceAddPermissionToGroup' and result_text = 'FAILED')
    loop
    dbms_output.put_line(wrec.full_url||chr(10)||chr(13)||'jdata is :'||wrec.jdata);
	/*Lets check Crowd and Confluence are synced so group is available to join*/
    select json_value(wrec.jdata,'$.params[1]') into group_key from dual;
    if rest_get(confluence||'/rest/api/group/'||group_key) = 200 then
    res := rest_post(wrec.full_url, wrec.jdata);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Permission to space was granted'
                           else 'ERROR: cannot add permissions to Space.' end||'"
}';
    dbms_output.put_line (res);
    update atlassian_callrest_result 
    set result_code = json_value(res, '$.response'),
        result_text = json_value(res, '$.result'),
        result_msg = res,
        date_call = sysdate
    where   system_name = 'confluence' and method = 'confluenceAddPermissionToGroup' 
            and full_url = wrec.full_url and jdata = wrec.jdata;
    end if;
    end loop;
end; --confluence   

begin --jira
for wrec in (select full_url,jdata from atlassian_callrest_result where system_name = 'jira' and method = 'jiraSetGroupToProjectRole' and result_text = 'FAILED')
    loop
    dbms_output.put_line(wrec.full_url||chr(10)||chr(13)||'jdata is :'||wrec.jdata);
	/*Lets check Crowd and Jira are synced so group is available to join*/
    select json_value(wrec.jdata,'$.categorisedActors."atlassian-group-role-actor"[0]') into group_key from dual;
    if rest_get(jira||'/rest/api/2/group/member?groupname='||group_key) = 200 then
    res := rest_put_json(wrec.full_url,wrec.jdata);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Permission to group '||group_key||' for JIRA project was granted'
                           else 'ERROR: cannot add permissions to group '||group_key||'.' end||'"
}';
    dbms_output.put_line (res);
    update atlassian_callrest_result 
    set result_code = json_value(res, '$.response'),
        result_text = json_value(res, '$.result'),
        result_msg = res,
        date_call = sysdate
    where   system_name = 'jira' and method = 'jiraSetGroupToProjectRole' 
            and full_url = wrec.full_url and jdata = wrec.jdata;
    end if;
    end loop;
end; --jira   
end fixGroupsPermissions;


--Check atlassian servers availability
procedure checkServers
as
res pls_integer;
begin
utl_http.set_transfer_timeout(2);
for i in (select url from atlassian_servers)
loop
begin
res := rest_get(i.url);
if res = 200 then 
    update atlassian_servers 
    set 
    status = 'up', 
    sk_label = sk_value || ' <span class="fa fa-circle" style="color:#4cd964;font-size:1.4em;" title="Server ' || sk_value ||' is up"></span>',
    status_code = 200,
    checked = sysdate
    where url=i.url;
else 
    update atlassian_servers 
            set status = 'down', 
            sk_label = sk_value || ' <span class="fa fa-circle" style="color:#ff3b30;font-size:1.4em;" title="Server ' || sk_value ||' is down"></span>',
            status_code = res, 
            checked = sysdate 
            where url=i.url;
end if;
exception
        when others then
        dbms_output.put_line('ERROR'||i.url);
            update atlassian_servers 
            set status = 'down', 
            sk_label = sk_value || ' <span class="fa fa-circle" style="color:#ff3b30;font-size:1.4em;" title="Server ' || sk_value ||' is down"></span>',
            status_code = NULL, 
            checked = sysdate 
            where url=i.url;
end;
end loop;
end checkServers;
/*
   _   _   _   _   _  
  / \ / \ / \ / \ / \ 
 ( C | R | O | W | D )
  \_/ \_/ \_/ \_/ \_/

*/

--Check Crowd user existence
function crowdCheckUser (user_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/user?username=';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(user_name);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := case res when 200 then 'SUCCESS' else 'FAILED' end;  
  dbms_output.put_line(res);
  return res;
end crowdCheckUser;

--Check Crowd group existence
function crowdCheckGroup (group_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group?groupname=';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(group_name);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := case res when 200 then 'SUCCESS' else 'FAILED' end;
  return res;
end crowdCheckGroup;

-- Create group in Crowd
function crowdAddGroup (group_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method;
  dbms_output.put_line(url);
  jdata :=
  '{"name": "'||upper(group_name)||'",
    "type": "GROUP",
    "active": true}';
  dbms_output.put_line (jdata);
  res := rest_post(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Group '||upper(group_name)||' is successfully created'
                           when 400 then 'Group '||upper(group_name)||' already exists'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res);
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata, project_key) 
  values('crowd','crowdAddGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null,       jdata,  upper(regexp_substr(group_name, '[a-zA-Z0-9]+')));
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdAddGroup;

--Delete group in Crowd
function crowdDeleteGroup (group_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group?groupname=';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(group_name);
  dbms_output.put_line('url to delete is '||url);
  res := rest_delete(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 204 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 204 then 'Group '||upper(group_name)||' was found and deleted'
                           when 404 then 'Group '||upper(group_name)||' could not be found'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res);
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key ) 
  values('crowd', 'crowdDeleteGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res, upper(regexp_substr(group_name, '[a-zA-Z0-9]+')));
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdDeleteGroup;

--Add user to group in Crowd
function crowdAddUserToGroup (group_name in varchar2, user_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group/user/direct?groupname=';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(group_name);
  dbms_output.put_line(url);
  jdata :=
  '{
    "name": "'||upper(user_name)||'"
    }';
  dbms_output.put_line (jdata);
  res := rest_post(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'User '||upper(user_name)||' is successfully added as a member of the group '||upper(group_name)
                           when 400 then 'User '||upper(user_name)||' could not be found'
                           when 404 then 'Group '||upper(group_name)||' could not be found'
                           when 409 then 'User '||upper(user_name)||' is already a direct member of the group '||upper(group_name)
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res);
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
  values('crowd',     'crowdAddUserToGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        upper(regexp_substr(group_name, '[a-zA-Z0-9]+')));
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdAddUserToGroup;

--Remove user from group in Crowd
function crowdRemoveUserFromGroup (group_name in varchar2, user_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group/user/direct';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||'?groupname='||upper(group_name)||'&username='||upper(user_name);
  dbms_output.put_line('url to delete is '||url);
  res := rest_delete(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 204 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 204 then 'User '||upper(user_name)||' successfully removed from '||upper(group_name)
                           when 404 then 'User or group could not be found'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line(res);
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
  values('crowd', 'crowdRemoveUserFromGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,   upper(regexp_substr(group_name, '[a-zA-Z0-9]+')));
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdRemoveUserFromGroup;

/*
   _   _   _   _  
  / \ / \ / \ / \ 
 ( J | I | R | A )
  \_/ \_/ \_/ \_/ 

*/

--Check project availability in Jira
function jiraIsProjectExist (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project/';
  url varchar2(512);
  res varchar2(1024);
begin
  url := jira||method||upper(pr_key);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := case res when 200 then 'SUCCESS' else 'FAILED' end;
  return res;
end jiraIsProjectExist;

--Create project in Jira
function jiraCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project';
  url varchar2(512);
  jdata varchar2(4000);
  res varchar2(1024);
  cres varchar2(1024); 
begin
  url := jira||method;
  dbms_output.put_line(url);
  jdata :=
  '{
    "key": "'||upper(pr_key)||'",
    "name": "'||upper(pr_name)||'",
    "projectTypeKey": "software",
    "description": "'||replace(pr_desc,'"','\"')||'",
    "lead": "'||upper(t_lead)||'",
    "url": "'||jira||'/projects/'||upper(pr_key)||'"
  }';
  dbms_output.put_line (jdata);
  if jiraIsProjectExist(upper(pr_key)) = 'FAILED' then
    res := rest_post(url,jdata);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Jira project '||upper(pr_name)||' is successfully created'
                           when 400 then 'Jira project '||upper(pr_name)||' could not be created. Request is not valid'
                           when 401 then 'Jira project '||upper(pr_name)||' could not be created. User is not logged in'
                           when 403 then 'Jira project '||upper(pr_name)||' could not be created. User does not have rights to create projects'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res); 
    insert into atlassian_callrest_result 
          (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata,project_key) 
    values('jira', 'jiraCreateProject',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
    commit; --so that raise_application_error does not roll back the transaction and we still have a log
    select json_value(res, '$.result') into res from dual;
        if res = 'SUCCESS' then
        insert into atlassian_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_key),'PROJECT','JIRA','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, jira||'/projects/'||upper(pr_key),upper(pr_key),null,upper(t_lead),null,0);
            if crowdCheckGroup(upper(pr_key)||'-JIRA-DEVELOPERS') = 'FAILED' then
                if crowdAddGroup(upper(pr_key)||'-JIRA-DEVELOPERS') = 'SUCCESS' then
                    if crowdAdduserToGroup(upper(pr_key)||'-JIRA-DEVELOPERS', upper(t_lead)) = 'SUCCESS' then
                        cres := jiraSetGroupToProjectRole(upper(pr_key));
                    else raise_application_error(-20400, 'CROWD Error: an error occurred while adding a user'||upper(t_lead)||' to group'||upper(pr_key)||'-JIRA-DEVELOPERS');
                    end if;
                else raise_application_error(-20401, 'CROWD Error: an error occurred while creating the group '||upper(pr_key)||'-JIRA-DEVELOPERS');
                end if;
            else raise_application_error(-20402, 'CROWD Error: Group '||upper(pr_key)||'-JIRA-DEVELOPERS  already exists!  ');
            end if;
        else raise_application_error(-20403, 'JIRA Error: возникла ошибка при создании проекта '||upper(pr_key)||' ');
        end if;
    else raise_application_error(-20410, 'JIRA Error: Проект '||upper(pr_key)||' уже существует. Выберите другое назнвание или обратитесь в поддержку.');
    end if;
  return res;
end jiraCreateProject;

--Delete project in Jira
function jiraDeleteProject (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project/';
  url varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
   x number := 0;
begin
  url := jira||method||upper(pr_key);
  dbms_output.put_line('url to delete is '||url);
  if jiraIsProjectExist(upper(pr_key)) = 'SUCCESS' then
    --res := rest_delete(url);
    --if res = '-200' then
        loop
            res := rest_delete(url);
            x := x+1;
        exit when res <> '-200' or x>3;
        end loop;
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 204 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 204 then 'Project '||upper(pr_key)||' is successfully deleted.'
                           when 401 then 'User is not logged in'
                           when 403 then 'Currently authenticated user does not have permission to delete the project.'
                           when 404 then 'Project '||upper(pr_key)||' does not exist.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values('jira','jiraDeleteProject',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        pr_key);
    commit; --so that raise_application_error does not roll back the transaction and we still have a log
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'PROJECT' and system_name = 'JIRA'; 
        cres := crowdDeleteGroup(upper(pr_key)||'-JIRA-DEVELOPERS'); 
    else raise_application_error(-20405, 'JIRA Error: возникла ошибка при удалении проекта '||upper(pr_key)||'!  ');
    end if;
  else 
    delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'PROJECT' and system_name = 'JIRA';
    cres := crowdDeleteGroup(upper(pr_key)||'-JIRA-DEVELOPERS');
    return 'SUCCESS';
  end if;
  return res;
end jiraDeleteProject;

--Assign a group from Crowd to the Developers role in jira  PUT /rest/api/2/project/{projectIdOrKey}/role/{id}
function        jiraSetGroupToProjectRole(pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project/'||upper(pr_key)||'/role/'||jiraRoleId; 
  url varchar2(512);
  res varchar2(1024);
  jdata varchar2(1024);
begin
  url := jira||method;
  dbms_output.put_line(url);
  jdata := '{
"id":"'||jiraRoleId||'",
"categorisedActors": {"atlassian-group-role-actor":["'||upper(pr_key)||'-JIRA-DEVELOPERS"]}
}';
/* If there is no group, then we write data to ATLASSIAN_CALLREST_RESULT and then every 5 minutes we process it to assign permissions.*/
  insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,result_text,result_msg, jdata, project_key) 
    values('jira','jiraSetGroupToProjectRole',url,sysdate,'-200','FAILED','{"message":"Group permission to Jira project '||upper(pr_key)||' scheduled."}',jdata,pr_key);
    res := 'SUCCESS';
--  end if;  
  return res;
end jiraSetGroupToProjectRole;

/*
   _   _   _   _   _   _   _   _   _  
  / \ / \ / \ / \ / \ / \ / \ / \ / \ 
 ( B | I | T | B | U | C | K | E | T )
  \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
  
*/
--Check project availability in Bitbucket
function bitbucketIsProjectExist (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects/';
  url varchar2(512);
  res varchar2(1024);
begin
  url := bitbucket||method||upper(pr_key);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := case res when 200 then 'SUCCESS' else 'FAILED' end;
  return res;
end bitbucketIsProjectExist;

--Create a project in Bitbucket
function bitbucketCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
begin
  url := bitbucket||method;
  dbms_output.put_line(url);
  jdata :=
  '{
    "key": "'||upper(pr_key)||'",
    "name": "'||upper(pr_name)||'",
    "description": "'||replace(pr_desc,'"','\"')||'",
    "lead": "'||upper(t_lead)||'",
    "url": "'||bitbucket||'/projects/'||upper(pr_key)||'"
  }';
  dbms_output.put_line (jdata);
if bitbucketIsProjectExist(upper(pr_key)) = 'FAILED' then
  res := rest_post(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Bitbucket project '||upper(pr_name)||' is successfully created'
                           when 400 then 'Bitbucket project '||upper(pr_name)||' could not be created. Request is not valid'
                           when 401 then 'Bitbucket project '||upper(pr_name)||' could not be created. User is not logged in'
                           when 403 then 'Bitbucket project '||upper(pr_name)||' could not be created. User does not have rights to create projects'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata, project_key) 
  values('bitbucket', 'bitbucketCreateProject',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
  commit; --so that raise_application_error does not roll back the transaction and we still have a log
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    insert into atlassian_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_key),'PROJECT','BITBUCKET','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, bitbucket||'/projects/'||upper(pr_key),upper(pr_key),null,upper(t_lead),null,0);
    for i in 1..stashprefix.count
        loop
            if crowdCheckGroup(upper(pr_key)||stashprefix(i)) = 'FAILED' then
                if crowdAddGroup(upper(pr_key)||stashprefix(i))= 'SUCCESS' then
                    if stashprefix(i) != '-STASH-USERS' then
                        if crowdAdduserToGroup(upper(pr_key)||stashprefix(i), upper(t_lead)) = 'SUCCESS' then
                            cres := bitbucketAddGroupPermToProject(upper(pr_key), stashprefix(i)); --здесь не будет проверок, из-за синхронизации запустим джоб, что раз в 5 минут дождется синхронизации и добавит проава как надо
                        else raise_application_error(-20400, 'CROWD Error: an error occurred while adding a user'||upper(t_lead)||' to group'||upper(pr_key)||'-BITBUCKET-DEVELOPERS');
                        end if;
                    else cres := bitbucketAddGroupPermToProject(upper(pr_key), stashprefix(i));
                    end if;
                else raise_application_error(-20401, 'CROWD Error: an error occurred while creating the group '||upper(pr_key)||stashprefix(i));
                end if;
            else raise_application_error(-20402, 'CROWD Error: Group '||upper(pr_key)||stashprefix(i)||'  already exists!  ');
            end if;
        end loop;
  else raise_application_error(-20407, 'BITBUCKET Error: возникла ошибка при создании проекта '||upper(pr_key)||' ');
  end if;
else raise_application_error(-20410, 'BITBUCKET Error: Проект '||upper(pr_key)||'  already exists!');
end if;
  return res;
end bitbucketCreateProject;

--Create repository in Bitbucket
function bitbucketCreateRepository (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects/'||upper(pr_key)||'/repos';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(512);
  cres varchar2(512);
begin
  url := bitbucket||method;
  dbms_output.put_line(url);
  jdata :=
  '{
    "name": "'||upper(pr_name)||'REPO",
    "url": "'||bitbucket||'/projects/'||upper(pr_key)||'/repos/'||upper(pr_name)||'REPO/browse"
  }';
  dbms_output.put_line (jdata);
  res := rest_post(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Bitbucket repo  '||upper(pr_name)||'REPO is successfully created'
                           when 400 then 'Bitbucket repo  '||upper(pr_name)||'REPO could not be created. Request is not valid'
                           when 401 then 'Bitbucket repo  '||upper(pr_name)||'REPO could not be created. User is not logged in'
                           when 409 then 'Bitbucket repo  '||upper(pr_name)||'REPO could not be created. Repo with same name already exists'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key, jdata) 
  values('bitbucket', 'bitbucketCreateRepository',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res, pr_key, jdata);
  commit; --so that raise_application_error does not roll back the transaction and we still have a log
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    insert into atlassian_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_name)||'REPO','REPOSITORY','BITBUCKET','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, bitbucket||'/projects/'||upper(pr_key)||'/repos/'||upper(pr_name)||'REPO/browse',upper(pr_key),null,upper(t_lead),null,0);
    for i in 1..stashprefix.count
    loop
        cres := bitbucketAddGroupPermToRepo(upper(pr_key), stashprefix(i));
    end loop;
  end if;
  return res;
end bitbucketCreateRepository;

--Delete project in Bitbucket
function bitbucketDeleteProject (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects/';
  url varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
begin
  url := bitbucket||method||upper(pr_key);
  dbms_output.put_line('url to delete is '||url);
  if bitbucketIsProjectExist(upper(pr_key)) = 'SUCCESS' then
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 204 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 204 then 'Project '||upper(pr_key)||' is successfully deleted.'
                           when 401 then 'User is not logged in'
                           when 404 then 'Specified project does not exist'
                           when 409 then 'The project '||upper(pr_key)||' can not be deleted as it contains repositories.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values('bitbucket',  'bitbucketDeleteProject',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        pr_key);
    commit; --so that raise_application_error does not roll back the transaction and we still have a log
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'PROJECT' and system_name = 'BITBUCKET';
    --надо ли добавлять проверку наличия группы в Crowd?? Это увеличивает время работы функции (смотря как ответит сервер).
        for i in 1..stashprefix.count
            loop
                cres := crowdDeleteGroup(upper(pr_key)||stashprefix(i));
                if cres <> 'SUCCESS' then 
                    cres:=crowdDeleteGroup(upper(pr_key)||'-BITBUCKET-DEVELOPERS');
                --raise_application_error(-20404, 'CROWD Error: возникла ошибка при удалении группы '||upper(pr_key)||stashprefix(i)||'!  ');
                end if;
            end loop;   
    else raise_application_error(-20405, 'BITBUCKET Error: возникла ошибка при удалении проекта '||upper(pr_key)||'!  ');
    end if;
  else 
    delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'PROJECT' and system_name = 'BITBUCKET';
    for i in 1..stashprefix.count
            loop
                cres := crowdDeleteGroup(upper(pr_key)||stashprefix(i));
                if cres <> 'SUCCESS' then 
                    cres:=crowdDeleteGroup(upper(pr_key)||'-BITBUCKET-DEVELOPERS');
                --raise_application_error(-20404, 'CROWD Error: возникла ошибка при удалении группы '||upper(pr_key)||stashprefix(i)||'!  ');
                end if;
            end loop;
    res := 'SUCCESS';
  --raise_application_error(-20406, 'BITBUCKET Error: возникла ошибка при удалении проекта '||upper(pr_key)||'! Проекта не существует.  ');
  end if;
  return res;
end bitbucketDeleteProject;

--Удаление репозитория в Bitbucket
function bitbucketDeleteRepository (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects/'||upper(pr_key)||'/repos/';
  url varchar2(512);
  res varchar2(1024);
 -- cres varchar2(1024);
begin
  url := bitbucket||method||upper(pr_key)||'REPO';
  dbms_output.put_line('url to delete is '||url);
  if bitbucketIsProjectExist(upper(pr_key)) = 'SUCCESS' then
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 202 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 202 then 'Repository scheduled for deletion.'
                           when 204 then 'No repository matching the supplied projectKey and repositorySlug was found.'
                           when 401 then 'The currently authenticated user has insufficient permissions to delete the repository.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values('bitbucket','bitbucketDeleteRepository',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        pr_key);
    commit; --so that raise_application_error does not roll back the transaction and we still have a log
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from atlassian_resources where resource_name = upper(pr_key)||'REPO' and resource_type = 'REPOSITORY' and system_name = 'BITBUCKET'; 
    else raise_application_error(-20405, 'BITBUCKET Error: возникла ошибка при удалении репозитория '||upper(pr_key)||'REPO!  ');
    end if;
  else
    delete from atlassian_resources where resource_name = upper(pr_key)||'REPO' and resource_type = 'REPOSITORY' and system_name = 'BITBUCKET';
    return 'SUCCESS';
  --raise_application_error(-20406, 'BITBUCKET Error: возникла ошибка при удалении репозитория '||upper(pr_key)||'REPO! Проекта '||upper(pr_key)||' не существует.  ');
  end if;
  return res;
end bitbucketDeleteRepository;

--Add rights to the repository of the created group in CROWD
function        bitbucketAddGroupPermToRepo (pr_key in varchar2, stashprefix in varchar2) return varchar2 
is
  method varchar2(256);
  url varchar2(512);
begin
    if stashprefix = '-STASH-ADMINS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/repos/'||upper(pr_key)||'REPO/permissions/groups?name='||upper(pr_key)||stashprefix||'&permission=REPO_ADMIN';
    elsif stashprefix = '-STASH-DEVELOPERS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/repos/'||upper(pr_key)||'REPO/permissions/groups?name='||upper(pr_key)||stashprefix||'&permission=REPO_WRITE';
    elsif stashprefix = '-STASH-USERS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/repos/'||upper(pr_key)||'REPO/permissions/groups?name='||upper(pr_key)||stashprefix||'&permission=REPO_READ';
    end if;
  url := bitbucket||method;
  dbms_output.put_line(url);
/* At the stage of creating the group, Bitbucket and Crowd are not yet synchronized.
We add the task to the queue, and the job will then distribute the rights, the server code is synchronized into groups
*/
    insert into atlassian_callrest_result 
          (system_name, method,                         full_url, date_call, result_code,   result_text,    result_msg, project_key) 
    values('bitbucket','bitbucketAddGroupPermToRepo',   url,      sysdate,   '-200',        'FAILED', '{"message":"Adding group permission '||upper(pr_key)||stashprefix||' to repo '||upper(pr_key)||'REPO scheduled"}',       pr_key);
  return 'FAILED';
end bitbucketAddGroupPermToRepo;

--Assign project rights to created groups in CROWD /REST/API/1.0/PROJECTS/{PROJECTKEY}/PERMISSIONS/GROUPS?PERMISSION&NAME
function        bitbucketAddGroupPermToProject (pr_key in varchar2, stashprefix in varchar2) return varchar2 
is
  method varchar2(256);
  url varchar2(512);
begin
    if stashprefix = '-STASH-ADMINS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/permissions/groups?permission=PROJECT_ADMIN&name=';
    elsif stashprefix = '-STASH-DEVELOPERS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/permissions/groups?permission=PROJECT_WRITE&name=';
    elsif stashprefix = '-STASH-USERS' then method := '/rest/api/1.0/projects/'||upper(pr_key)||'/permissions/groups?permission=PROJECT_READ&name=';
    end if;
    url := bitbucket||method||upper(pr_key)||stashprefix;
    dbms_output.put_line(url);
/* At the stage of creating the group, Bitbucket and Crowd are not yet synchronized.
We add the task to the queue, and the job will then distribute the rights, the server code is synchronized into groups
*/
    insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values('bitbucket',     'bitbucketAddGroupPermToProject',      url,      sysdate,   '-200', 'FAILED', '{"message":"Adding group permission '||upper(pr_key)||stashprefix||' to project '||upper(pr_key)||' scheduled"}',        pr_key);
    return 'FAILED';
end bitbucketAddGroupPermToProject;

/*
   _   _   _   _   _   _   _   _   _   _  
  / \ / \ / \ / \ / \ / \ / \ / \ / \ / \ 
 ( C | O | N | F | L | U | E | N | C | E )
  \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
  
*/

--Check project availability in Confluence GET /rest/api/space/{spaceKey}
function confluenceIsSpaceExist (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/space/';
  url varchar2(512);
  res varchar2(1024);
begin
  url := confluence||method||upper(pr_key);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := case res when 200 then 'SUCCESS' else 'FAILED' end;
  return res;
end confluenceIsSpaceExist;

--Create Space in Confluence POST /rest/api/space
function        confluenceCreateSpace (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/space/';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
begin
  url := confluence||method;
  dbms_output.put_line(url);
  jdata :=
  '{
    "key": "'||upper(pr_key)||'",
    "name": "'||upper(pr_name)||'",
    "description": {"plain":{"value":"'||replace(pr_desc,'"','\"')||'","representation":"plain"}},
    "url": "'||confluence||'/display/'||upper(pr_key)||'"
  }';
  dbms_output.put_line (jdata);
if confluenceIsSpaceExist(upper(pr_key)) = 'FAILED' then
  res := rest_post(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Confluence space '||upper(pr_name)||' is successfully created'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata,project_key) 
  values('confluence','confluenceCreateSpace',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
  commit; --so that raise_application_error does not roll back the transaction and we still have a log
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    insert into atlassian_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_key),'SPACE','CONFLUENCE','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, confluence||'/display/'||upper(pr_key),upper(pr_key),null,upper(t_lead),null,0);
    if crowdCheckGroup(upper(pr_key)||'-CONFLUENCE-DEVELOPERS') = 'FAILED' then
        if crowdAddGroup(upper(pr_key)||'-CONFLUENCE-DEVELOPERS')= 'SUCCESS' then
            if crowdAdduserToGroup(upper(pr_key)||'-CONFLUENCE-DEVELOPERS', upper(t_lead)) = 'SUCCESS' then
                  cres := confluenceAddPermissionToGroup(upper(pr_key)); --there will be no checks, because of synchronization, we will run a job that once every 5 minutes it will wait for synchronization and add the rights as necessary
                 return res;
            else raise_application_error(-20400, 'CROWD Error: an error occurred while adding a user'||upper(t_lead)||' to group'||upper(pr_key)||'-CONFLUENCE-DEVELOPERS');
            end if;
        else raise_application_error(-20401, 'CROWD Error: an error occurred while creating the group '||upper(pr_key)||'-CONFLUENCE-DEVELOPERS');
        end if;
    else raise_application_error(-20402, 'CROWD Error: Group '||upper(pr_key)||'-CONFLUENCE-DEVELOPERS  already exists!');
    end if;
  else raise_application_error(-20407, 'CONFLUENCE Error: an error occurred while creating the space '||upper(pr_key));
  end if;
else raise_application_error(-20410, 'CONFLUENCE Error: Space '||upper(pr_key)||'  already exists!');
end if;
  return res;
end confluenceCreateSpace;

--Confluence Space Removal DELETE /rest/api/space/{spaceKey}
function confluenceDeleteSpace (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/space/';
  url varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
begin
  url := confluence||method||upper(pr_key);
  dbms_output.put_line('url to delete is '||url);
  if confluenceIsSpaceExist(upper(pr_key)) = 'SUCCESS' then
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 202 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 202 then 'Space scheduled for deletion.'
                           when 204 then 'No Space matching the supplied projectKey.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values('bitbucket','confluenceDeleteSpace',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        pr_key);
    commit; --so that raise_application_error does not roll back the transaction and we still have a log
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'SPACE' and system_name = 'CONFLUENCE';
        cres := crowdDeleteGroup(upper(pr_key)||'-CONFLUENCE-DEVELOPERS');
    else raise_application_error(-20405, 'CONFLUENCE Error: an error occurred while deleting the space '||upper(pr_key)||'!  ');
    end if;
  else 
  delete from atlassian_resources where resource_name = upper(pr_key) and resource_type = 'SPACE' and system_name = 'CONFLUENCE';
  cres := crowdDeleteGroup(upper(pr_key)||'-CONFLUENCE-DEVELOPERS');
  return 'SUCCESS';
  end if;
  return res;
end confluenceDeleteSpace;

--Assign project rights to created group in CROWD with a prefix -CONFLUENCE-DEVELOPERS
function        confluenceAddPermissionToGroup (pr_key in varchar2) return varchar2 
is
/*This method is deprecated, I hope that when the normal REST is released, I will not work here anymore, so this is a problem for you, Padawan*/
  method varchar2(256) := '/rpc/json-rpc/confluenceservice-v2'; 
  url varchar2(512);
  res varchar2(1024);
  jdata varchar2(1024);
 -- cres varchar2(1024);
begin
  url := confluence||method;
  dbms_output.put_line(url);
  jdata := '{
"jsonrpc":"2.0",
"method":"addPermissionsToSpace",
"params": [["VIEWSPACE","EDITSPACE","EDITBLOG","CREATEATTACHMENT","COMMENT"],"'||upper(pr_key)||'-CONFLUENCE-DEVELOPERS","'||upper(pr_key)||'"]
}';
  insert into atlassian_callrest_result 
            (system_name, method, full_url, date_call, result_code,result_text,result_msg, jdata,project_key) 
    values('confluence','confluenceAddPermissionToGroup',url,sysdate,'-200','FAILED','{"message":"Group permission to Confluence space '||upper(pr_key)||' scheduled."}',jdata,pr_key);
    res := 'FAILED';  
  return res;
end confluenceAddPermissionToGroup;
/*
   _   _   _   _   _   _   _   _   _   _   _  
  / \ / \ / \ / \ / \ / \ / \ / \ / \ / \ / \ 
 ( A | R | T | I | F | A | C | T | O | R | Y )
  \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
  
*/

--Check availability of repository in Artifactory
function    artifactoryIsRepoExist(pr_key in varchar2) return varchar2
is
  method varchar2(64)  := '/artifactory/api/repositories/';
  url varchar2(256);
  total_check pls_integer   := 0;
  v_check pls_integer       := 0;
  res varchar2(64);
begin
    for i in 1..repoprefix.count
    loop
        url := artifactory||method||lower(pr_key)||repoprefix(i);
        dbms_output.put_line(url);
        res := rest_get(url);
        dbms_output.put_line(res);
        select decode(res, 200, 1, 0) into v_check from dual;
        total_check := total_check + v_check;
        dbms_output.put_line('v_check is '||v_check||'; total_check is '||total_check);
    end loop;
    if total_check = 0 then return 'FAILED';
    else return 'SUCCESS';
    end if;
end artifactoryIsRepoExist;

--Creating repositories in Artifactory
function artifactoryCreateRepository(pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(128) := '/artifactory/api/repositories/';
  url varchar2(512);
  pr_url varchar2(512);
  jdata varchar2(512);
  res varchar2(512);
  cres varchar2(512);
begin
--Create a group in Crowd and add the creator there
    if crowdCheckGroup(upper(pr_key)||'-ARTIFACTORY-DEVELOPERS') = 'FAILED' then
        if crowdAddGroup(upper(pr_key)||'-ARTIFACTORY-DEVELOPERS')= 'SUCCESS' then
            if crowdAdduserToGroup(upper(pr_key)||'-ARTIFACTORY-DEVELOPERS', upper(t_lead)) = 'SUCCESS' then
                 cres := 'SUCCESS';
            else raise_application_error(-20400, 'CROWD Error: an error occurred while adding a user'||upper(t_lead)||' to group'||upper(pr_key)||'-ARTIFACTORY-DEVELOPERS');
            end if;
        else raise_application_error(-20401, 'CROWD Error: an error occurred while creating the group '||upper(pr_key)||'-ARTIFACTORY-DEVELOPERS');
        end if;
    else raise_application_error(-20402, 'CROWD Error: Group '||upper(pr_key)||'-ARTIFACTORY-DEVELOPERS  already exists!  ');
    end if;
--Now we are creating the same group in Artifactory
    if artifactoryCreateGroup(pr_key) = 'SUCCESS' then
        for i in 1..repoprefix.count
            loop
                url := artifactory||method||lower(pr_key)||repoprefix(i);
                pr_url := artifactory||'/artifactory/webapp/#/artifacts/browse/tree/General/'||lower(pr_key)||repoprefix(i);
                dbms_output.put_line(url);
            jdata :=
            '{
"key": "'||lower(pr_key)||repoprefix(i)||'",
"rclass":"local",
"packageType":"'||case regexp_substr(repoprefix(i), '[a-z]+') when 'mvn' then 'maven' else regexp_substr(repoprefix(i), '[a-z]+') end||'",
"repoLayoutRef":"'||case regexp_substr(repoprefix(i), '[a-z]+') when 'mvn' then 'maven-2-default' else 'simple-default' end||'",
"description":"'||replace(pr_desc,'"','\"')||'",
"propertySets": [ "artifactory"],
"notes":"owner:'||upper(t_lead)||'"
}';
          dbms_output.put_line (jdata);
          res := rest_put_json(url,jdata);
          res := 
        '{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Artifactory repo '||lower(pr_key)||repoprefix(i)||' is successfully created'
                                   else 'ERROR' end||'"
        }';
          dbms_output.put_line (res); 
          insert into atlassian_callrest_result 
                (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata, project_key) 
          values('artifactory','artifactoryCreateRepository',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
          commit; --so that raise_application_error does not roll back the transaction and we still have a log
          select json_value(res, '$.result') into res from dual;
          if res = 'SUCCESS' then
            insert into atlassian_resources
                        (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
                values  (lower(pr_key)||repoprefix(i),'REPOSITORY','ARTIFACTORY','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, pr_url,upper(pr_key),null,upper(t_lead),null,0);
            -- add permissions    
            cres := artifactoryCreatePermission(pr_key, repoprefix(i), t_lead);
          else raise_application_error(-20450,'Artifactory error: Could not create repository '||lower(pr_key)||repoprefix(i));
          end if;
          end loop;
        end if;
return res;
end artifactoryCreateRepository;

--Delete Artifactory Repositories
function    artifactoryDeleteRepository(repo_name in varchar2) return varchar2
is
  method varchar2(256) := '/artifactory/api/repositories/';
  url varchar2(512);
  res varchar2(1024);
 -- cres varchar2(1024);
begin
if rest_get(artifactory||'/artifactory/api/repositories/'||repo_name) = 200 then
  url := artifactory||method||repo_name;
  dbms_output.put_line('url to delete is '||url);
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Repository '||repo_name||' and all its content have been removed successfully.'
                           when 404 then 'No Repository matching the supplied name.'
                           else 'ERROR' end||'"
}';
    dbms_output.put_line (res);
    insert into atlassian_callrest_result 
            (system_name,   method,                        full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
    values  ('artifactory','artifactoryDeleteRepository',  url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        upper(regexp_substr(repo_name, '[a-zA-Z0-9]+')));
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from atlassian_resources where resource_name = repo_name and resource_type = 'REPOSITORY' and system_name = 'ARTIFACTORY';
        return artifactoryDeletePermission(repo_name);
    else raise_application_error(-20405, 'Atrifactory: an error occurred while deleting the repository '||repo_name||'.');
    end if;
else
    delete from atlassian_resources where resource_name = repo_name and resource_type = 'REPOSITORY' and system_name = 'ARTIFACTORY';
    return 'SUCCESS';
    end if;
end artifactoryDeleteRepository;

--Create group in the Artifactory
function        artifactoryCreateGroup(pr_key in varchar2) return varchar2
is
  method varchar2(128) := '/artifactory/api/security/groups/';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(512);
begin
    url := artifactory||method||lower(pr_key)||'-artifactory-developers';
    dbms_output.put_line(url);
    jdata :=
'{
  "name": "'||lower(pr_key)||'-artifactory-developers",
  "autoJoin": false,
  "realm": "crowd",
  "adminPrivileges": false
}';
  dbms_output.put_line (jdata);
  res := rest_put_json(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Artifactory group '||lower(pr_key)||'-artifactory-developers is successfully created'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata,project_key) 
  values('artifactory','artifactoryCreateGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
  commit; --so that raise_application_error does not roll back the transaction and we still have a log
  select json_value(res, '$.result') into res from dual;
  return res;
end artifactoryCreateGroup;

--Create Artifactory permissions
function        artifactoryCreatePermission(pr_key in varchar2, prefix in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(128) := '/artifactory/api/security/permissions/';
  url varchar2(512);
  jdata varchar2(512);
  res varchar2(512);
begin
    url := artifactory||method||'permission-'||lower(pr_key)||prefix;
    dbms_output.put_line(url);
    jdata :=
'{  
  "name": "permission-'||lower(pr_key)||prefix||'",
  "includesPattern": "**",
  "excludesPattern": "",
  "repositories": [
    "'||lower(pr_key)||prefix||'"
  ],
  "principals": {
    "users": {
      "'||lower(t_lead)||'": [
        "r",
        "d",
        "w",
        "n"
      ]
    },
    "groups": {
      "'||lower(pr_key)||'-artifactory-developers": [
        "r",
        "w",
        "n"
      ]
    }
  }
}';
  dbms_output.put_line (jdata);
  res := rest_put_json(url,jdata);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 201 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 201 then 'Artifactory permission-'||lower(pr_key)||prefix||' is successfully created'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_id, jdata,project_key) 
  values('artifactory','artifactoryCreatePermission',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null, jdata,pr_key);
  commit; --so that raise_application_error does not roll back the transaction and we still have a log
  select json_value(res, '$.result') into res from dual;
  return res;
end artifactoryCreatePermission;

--Remove the group in the Artifactory as well as from Crowd
function        artifactoryDeleteGroup(pr_key in varchar2) return varchar2
is
  method varchar2(128) := '/artifactory/api/security/groups/';
  url varchar2(512);
  res varchar2(512);
begin
    url := artifactory||method||lower(pr_key)||'-artifactory-developers';
    dbms_output.put_line(url);
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Artifactory group '||lower(pr_key)||'-artifactory-developers is successfully deleted'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
  values('artifactory','artifactoryDeleteGroup',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        pr_key);
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    if crowdCheckGroup(upper(pr_key)||'-ARTIFACTORY-DEVELOPERS') = 'SUCCESS' then
        return crowdDeleteGroup(upper(pr_key)||'-ARTIFACTORY-DEVELOPERS');
    else return 'SUCCESS';
    end if;
  else raise_application_error (-20411, 'Artifactory error: Группы '||lower(pr_key)||'-artifactory-developers не существует');
  end if;
end artifactoryDeleteGroup;

--delete Artifactory permissions
function        artifactoryDeletePermission(repo_name in varchar2) return varchar2
is
  method varchar2(128) := '/artifactory/api/security/permissions/';
  url varchar2(512);
  res varchar2(512);
begin
    url := artifactory||method||'permission-'||repo_name;
    dbms_output.put_line(url);
    res := rest_delete(url);
    res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Artifactory permission-'||repo_name||' DELETED'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line (res); 
  insert into atlassian_callrest_result 
        (system_name, method, full_url, date_call, result_code,                   result_text,                 result_msg, project_key) 
  values('artifactory','artifactoryDeletePermission',      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        upper(regexp_substr(repo_name, '[a-zA-Z0-9]+')));
  select json_value(res, '$.result') into res from dual;
  return res;
end artifactoryDeletePermission;
end atlassian;
/
