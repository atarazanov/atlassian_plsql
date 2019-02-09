CREATE OR REPLACE package atlassian as 
/* created by A. Tarazanov 2019-02-01*/
--API Basic authorization
auth_header varchar2(256) := 'Basic ***REMOVED***';
--hosts
crowd       varchar2(256) := 'http://crowdft***REMOVED***';
jira        varchar2(256) := 'http://jiraft***REMOVED***';
bitbucket   varchar2(256) := 'http://gitft***REMOVED***';
--functions
function        rest_post (the_url in varchar2, jdata in varchar2) return pls_integer;
function        rest_delete (the_url in varchar2) return pls_integer;
function        rest_get (the_url in varchar2) return pls_integer;
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

--Bitbucket projects
function        bitbucketIsProjectExist (pr_key in varchar2) return varchar2;
function        bitbucketCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2;
/* To DO
bitbucketCreateRepository
bitbucketDeleteProject
bitbucketAddUsersPermissionToProject
bitbucketAddUsersPermissionToRepo

bitbucketAddGroupPermissionToProject
bitbucketDeleteRepository
*/
end atlassian;
/


CREATE OR REPLACE package body atlassian as

--отправить JSON запросом POST
function rest_post (the_url in varchar2, jdata in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
  response varchar2(32000);
BEGIN
  utl_http.set_body_charset('UTF-8'); --Catalina cannot read request body in AL32UTF8
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'POST','HTTP/1.1');
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'content-type', 'application/json');
  utl_http.set_header(req, 'accept', 'application/json');
  utl_http.set_header(req, 'authorization', auth_header);
  utl_http.set_header(req, 'content-length', lengthb(jdata)); -- lengthB means Binary lenth
  --utl_http.write_text(req, convert(jdata, 'UTF8','AL32UTF8')); -- this doesnt work for us :(
  utl_http.write_raw(req, utl_raw.cast_to_raw(jdata)); -- we will send BODY in raw
  
  resp := utl_http.get_response(req);
  dbms_output.put_line('post status code is '||resp.status_code);
 -- UTL_HTTP.read_text(resp, response); -- Catalina может отдавать много данных, не влазит в буфер, отключил
  --dbms_output.put_line(response);
  return resp.status_code;
  utl_http.end_response(resp);
  exception WHEN others THEN return '-200';
end rest_post;

--отправить запрос DELETE
function rest_delete (the_url in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'DELETE','HTTP/1.1');
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'accept', 'application/json');
  utl_http.set_header(req, 'authorization', auth_header);
  resp := utl_http.get_response(req);
  dbms_output.put_line(resp.status_code);
  return resp.status_code;
  utl_http.end_response(resp);
  exception WHEN others THEN return '-200';
end rest_delete;

--отправить запрос GET
function rest_get (the_url in varchar2) return pls_integer
is
  req   utl_http.req;
  resp  utl_http.resp;
BEGIN
  utl_http.set_transfer_timeout(10);
  req := utl_http.begin_request(the_url, 'GET','HTTP/1.1');
  utl_http.set_header(req, 'user-agent', 'utl_http');
  utl_http.set_header(req, 'accept', 'application/json');
  utl_http.set_header(req, 'authorization', auth_header);
  resp := utl_http.get_response(req);
  dbms_output.put_line(resp.status_code);
  return resp.status_code;
  utl_http.end_response(resp);
  exception WHEN others THEN return '-200';
end rest_get;

--Проверить наличие пользователя в Crowd
function crowdCheckUser (user_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/user?username=';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(user_name);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'User '||upper(user_name)||' exists'
                           when 404 then 'User '||upper(user_name)||' could not be found'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line(res);
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  dbms_output.put_line(res);
  return res;
end crowdCheckUser;

--Проверить наличие группы в Crowd
function crowdCheckGroup (group_name in varchar2) return varchar2
is
  method varchar2(256) := '/crowd/rest/usermanagement/1/group?groupname=';
  url varchar2(512);
  res varchar2(1024);
begin
  url := crowd||method||upper(group_name);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Group '||upper(group_name)||' exists'
                           when 404 then 'Group '||upper(group_name)||' could not be found'
                           else 'ERROR' end||'"
}';
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  dbms_output.put_line(res);
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdCheckGroup;

--Создать группу в Crowd
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdAddGroup;

--Удаление группы в Crowd
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdDeleteGroup;

--Добавить пользователя в группу в Crowd
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdAddUserToGroup;

--Удалить пользователя из группы в Crowd
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('crowd',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end crowdRemoveUserFromGroup;

--Проверить наличие проекта в Jira
function jiraIsProjectExist (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project/';
  url varchar2(512);
  res varchar2(1024);
begin
  url := jira||method||upper(pr_key);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Project '||upper(pr_key)||' exists'
                           when 404 then 'Project is not found'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line(res);
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('jira',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end jiraIsProjectExist;

--Создание проекта в Jira
function jiraCreateProject (pr_name in varchar2, pr_key in varchar2, pr_desc in varchar2, t_lead in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project';
  url varchar2(512);
  jdata varchar2(512);
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
    "description": "'||pr_desc||'",
    "lead": "'||upper(t_lead)||'",
    "url": "'||jira||'/projects/'||upper(pr_key)||'"
  }';
  dbms_output.put_line (jdata);
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('jira',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  commit; --для того, чтобы raise_application_error не откатил транзакицю и у нас остался лог
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    insert into ***REMOVED***_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_key),'PROJECT','JIRA','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, jira||'/projects/'||upper(pr_key),upper(pr_key),null,upper(t_lead),null,0);
    cres := crowdCheckGroup(upper(pr_key)||'-JIRA-DEVELOPERS');
        if cres = 'FAILED' then 
            cres := crowdAddGroup(upper(pr_key)||'-JIRA-DEVELOPERS');
            if cres = 'SUCCESS' then 
                cres := crowdAdduserToGroup(upper(pr_key)||'-JIRA-DEVELOPERS', upper(t_lead));
                if cres <> 'SUCCESS' then raise_application_error(-20400, 'CROWD Error: возникла ошибка при добавления пользователя '||upper(t_lead)||' в группу '||upper(pr_key)||'-JIRA-DEVELOPERS');
                end if;
            else raise_application_error(-20401, 'CROWD Error: возникла ошибка при создании группы '||upper(pr_key)||'-JIRA-DEVELOPERS');
            end if;
        else raise_application_error(-20402, 'CROWD Error: Группа '||upper(pr_key)||'-JIRA-DEVELOPERS уже существует! Обратитесь в поддержку StarterKit.');
        end if;
    else raise_application_error(-20403, 'JIRA Error: возникла ошибка при создании проекта '||upper(pr_key)||'!Обратитесь в поддержку StarterKit.');
    end if;  
  return res;
end jiraCreateProject;

--Удаление проекта в Jira
function jiraDeleteProject (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/2/project/';
  url varchar2(512);
  res varchar2(1024);
  cres varchar2(1024);
begin
  url := jira||method||upper(pr_key);
  dbms_output.put_line('url to delete is '||url);
  if jiraIsProjectExist(upper(pr_key)) = 'SUCCESS' then
    res := rest_delete(url);
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
    insert into ***REMOVED***_callrest_result 
            (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
    values('jira',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
    commit; --для того, чтобы raise_application_error не откатил транзакицю и у нас остался лог
    select json_value(res, '$.result') into res from dual;
    if res = 'SUCCESS' then
        delete from ***REMOVED***_resources where resource_name = upper(pr_key) and resource_type = 'PROJECT' and system_name = 'JIRA';
    --надо ли добавлять проверку наличия группы в Crowd?? Это увеличивает время работы функции (смотря как ответит сервер).
        cres := crowdDeleteGroup(upper(pr_key)||'-JIRA-DEVELOPERS');
        if cres <> 'SUCCESS' then raise_application_error(-20404, 'CROWD Error: возникла ошибка при удалении группы '||upper(pr_key)||'-JIRA-DEVELOPERS! Обратитесь в поддержку StarterKit.');
        end if; 
    else raise_application_error(-20405, 'JIRA Error: возникла ошибка при удалении проекта '||upper(pr_key)||'! Обратитесь в поддержку StarterKit.');
    end if;
  else raise_application_error(-20406, 'JIRA Error: возникла ошибка при удалении проекта '||upper(pr_key)||'! Проекта не существует. Обратитесь в поддержку StarterKit.');
  end if;
  return res;
end jiraDeleteProject;

--Проверить наличие проекта в Bitbucket
function bitbucketIsProjectExist (pr_key in varchar2) return varchar2
is
  method varchar2(256) := '/rest/api/1.0/projects/';
  url varchar2(512);
  res varchar2(1024);
begin
  url := bitbucket||method||upper(pr_key);
  dbms_output.put_line(url);
  res := rest_get(url);
  res := 
'{
"response":'    ||res||',
"result":"'     ||case res when 200 then 'SUCCESS' else 'FAILED' end||'",
"message":"'    ||case res when 200 then 'Project '||upper(pr_key)||' exists'
                           when 404 then 'Project is not found'
                           else 'ERROR' end||'"
}';
  dbms_output.put_line(res);
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('bitbucket',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  select json_value(res, '$.result') into res from dual;
  return res;
end bitbucketIsProjectExist;

--Создание проекта в Bitbucket
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
    "description": "'||pr_desc||'",
    "lead": "'||upper(t_lead)||'",
    "url": "'||bitbucket||'/projects/'||upper(pr_key)||'"
  }';
  dbms_output.put_line (jdata);
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
  insert into ***REMOVED***_callrest_result 
        (system_name, method_id, full_url, date_call, result_code,                   result_text,                 result_msg, project_id) 
  values('bitbucket',     null,      url,      sysdate,   json_value(res, '$.response'), json_value(res, '$.result'), res,        null);
  commit; --для того, чтобы raise_application_error не откатил транзакицю и у нас остался лог
  select json_value(res, '$.result') into res from dual;
  if res = 'SUCCESS' then
    insert into ***REMOVED***_resources
                (RESOURCE_NAME,RESOURCE_TYPE,SYSTEM_NAME,PROJECT_KEY,CREATED_BY,CREATION_DATE,DESCRIPTION,RESOURCE_URL,SYSTEM_KEY,ENV_ID,PRODUCTOWNER,PROJECT_ID,DEMO)
        values  (upper(pr_key),'PROJECT','BITBUCKET','S.'||upper(pr_key),upper(t_lead),sysdate, pr_desc, bitbucket||'/projects/'||upper(pr_key),upper(pr_key),null,upper(t_lead),null,0);
    cres := crowdCheckGroup(upper(pr_key)||'-BITBUCKET-DEVELOPERS');
        if cres = 'FAILED' then 
            cres := crowdAddGroup(upper(pr_key)||'-BITBUCKET-DEVELOPERS');
            if cres = 'SUCCESS' then 
                cres := crowdAdduserToGroup(upper(pr_key)||'-BITBUCKET-DEVELOPERS', upper(t_lead));
                if cres <> 'SUCCESS' then raise_application_error(-20400, 'CROWD Error: возникла ошибка при добавления пользователя '||upper(t_lead)||' в группу '||upper(pr_key)||'-BITBUCKET-DEVELOPERS');
                end if;
            else raise_application_error(-20401, 'CROWD Error: возникла ошибка при создании группы '||upper(pr_key)||'-BITBUCKET-DEVELOPERS');
            end if;
        else raise_application_error(-20402, 'CROWD Error: Группа '||upper(pr_key)||'-BITBUCKET-DEVELOPERS уже существует! Обратитесь в поддержку StarterKit.');
        end if;
    else raise_application_error(-20403, 'BITBUCKET Error: возникла ошибка при создании проекта '||upper(pr_key)||'!Обратитесь в поддержку StarterKit.');
    end if;  
  return res;
end bitbucketCreateProject;

end atlassian;
/
