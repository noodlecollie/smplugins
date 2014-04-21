<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<title>TF2Items - /pawn/tf2items_manager.sp - Changes - LimeTech.org Issue Tracker</title>
<meta name="description" content="Redmine" />
<meta name="keywords" content="issue,bug,tracker" />
<meta name="csrf-param" content="authenticity_token"/>
<meta name="csrf-token" content="tYNDGR9B2z6ERCz+DhwrcJtKQbiD0KeclWvaftSSbIg="/>
<link rel='shortcut icon' href='/favicon.ico?1280193474' />
<link href="/stylesheets/application.css?1304286224" media="all" rel="stylesheet" type="text/css" />

<script src="/javascripts/prototype.js?1304286224" type="text/javascript"></script>
<script src="/javascripts/effects.js?1280193474" type="text/javascript"></script>
<script src="/javascripts/dragdrop.js?1280193474" type="text/javascript"></script>
<script src="/javascripts/controls.js?1280193474" type="text/javascript"></script>
<script src="/javascripts/application.js?1304286224" type="text/javascript"></script>
<script type="text/javascript">
//<![CDATA[
Event.observe(window, 'load', function(){ new WarnLeavingUnsaved('The current page contains unsaved text that will be lost if you leave this page.'); });
//]]>
</script>

<!--[if IE 6]>
    <style type="text/css">
      * html body{ width: expression( document.documentElement.clientWidth < 900 ? '900px' : '100%' ); }
      body {behavior: url(/stylesheets/csshover.htc?1280193474);}
    </style>
<![endif]-->

<!-- page specific tags -->

  <script src="/javascripts/repository_navigation.js?1280193474" type="text/javascript"></script>
</head>
<body class="controller-repositories action-changes">
<div id="wrapper">
<div id="wrapper2">
<div id="top-menu">
    <div id="account">
        <ul><li><a href="/login" class="login">Sign in</a></li>
<li><a href="/account/register" class="register">Register</a></li></ul>    </div>
    
    <ul><li><a href="/" class="home">Home</a></li>
<li><a href="/projects" class="projects">Projects</a></li>
<li><a href="http://www.redmine.org/guide" class="help">Help</a></li></ul></div>
      
<div id="header">
    
    <div id="quick-search">
        <form action="/search/index/tf2items" method="get">
        <input name="changesets" type="hidden" value="1" />
        <a href="/search/index/tf2items" accesskey="4">Search</a>:
        <input accesskey="f" class="small" id="q" name="q" size="20" type="text" />
        </form>
        
    </div>
    
    
    <h1>TF2Items</h1>
    
    
    <div id="main-menu">
        <ul><li><a href="/projects/tf2items" class="overview">Overview</a></li>
<li><a href="/projects/tf2items/activity" class="activity">Activity</a></li>
<li><a href="/projects/tf2items/roadmap" class="roadmap">Roadmap</a></li>
<li><a href="/projects/tf2items/issues" class="issues">Issues</a></li>
<li><a href="/projects/tf2items/news" class="news">News</a></li>
<li><a href="/projects/tf2items/wiki" class="wiki">Wiki</a></li>
<li><a href="/projects/tf2items/files" class="files">Files</a></li>
<li><a href="/projects/tf2items/repository" class="repository selected">Repository</a></li></ul>
    </div>
    
</div>

<div class="nosidebar" id="main">
    <div id="sidebar">        
        
        
    </div>
    
    <div id="content">
				
        

<div class="contextual">
  

<a href="/projects/tf2items/repository/statistics" class="icon icon-stats">Statistics</a>

<form action="/projects/tf2items/repository/changes/pawn/tf2items_manager.sp?rev=" id="revision_selector" method="get">  <!-- Branches Dropdown -->
      | Branch: 
    <select id="branch" name="branch"><option value=""></option>
<option value="default">default</option>
<option value="tf2items_2010">tf2items_2010</option></select>
  
  
  | Revision: 
  <input id="rev" name="rev" size="8" type="text" />
</form>
</div>

<h2>
  <a href="/projects/tf2items/repository/show">root</a>

    / <a href="/projects/tf2items/repository/show/pawn">pawn</a>


    / <a href="/projects/tf2items/repository/changes/pawn/tf2items_manager.sp">tf2items_manager.sp</a>





</h2>

<p>

<p>
History |

    <a href="/projects/tf2items/repository/entry/pawn/tf2items_manager.sp">View</a> |


    <a href="/projects/tf2items/repository/annotate/pawn/tf2items_manager.sp">Annotate</a> |

<a href="/projects/tf2items/repository/raw/pawn/tf2items_manager.sp">Download</a>
(15.3 kB)
</p>


</p>



<form action="/projects/tf2items/repository/diff/pawn/tf2items_manager.sp" method="get">
<table class="list changesets">
<thead><tr>
<th>#</th>
<th></th>
<th></th>
<th>Date</th>
<th>Author</th>
<th>Comment</th>
</tr></thead>
<tbody>



<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/f521801068ad" title="Revision 198:f521801068ad">198:f521801068ad</a></td>
<td class="checkbox"><input checked="checked" id="cb-1" name="rev" onclick="$('cbto-2').checked=true;" type="radio" value="f521801068ad" /></td>
<td class="checkbox"></td>
<td class="committed_on">08/01/2011 07:13 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Bumped version numbers. Removed useless plugins.</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/e5266f70d488" title="Revision 184:e5266f70d488">184:e5266f70d488</a></td>
<td class="checkbox"><input id="cb-2" name="rev" onclick="$('cbto-3').checked=true;" type="radio" value="e5266f70d488" /></td>
<td class="checkbox"><input checked="checked" id="cbto-2" name="rev_to" onclick="if ($('cb-2').checked==true) {$('cb-1').checked=true;}" type="radio" value="e5266f70d488" /></td>
<td class="committed_on">06/11/2010 04:43 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Created branch with new '2010' version.</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/480f68afcf02" title="Revision 173:480f68afcf02">173:480f68afcf02</a></td>
<td class="checkbox"><input id="cb-3" name="rev" onclick="$('cbto-4').checked=true;" type="radio" value="480f68afcf02" /></td>
<td class="checkbox"><input id="cbto-3" name="rev_to" onclick="if ($('cb-3').checked==true) {$('cb-2').checked=true;}" type="radio" value="480f68afcf02" /></td>
<td class="committed_on">21/08/2010 05:38 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Whoops</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/adbe7bd60fc4" title="Revision 172:adbe7bd60fc4">172:adbe7bd60fc4</a></td>
<td class="checkbox"><input id="cb-4" name="rev" onclick="$('cbto-5').checked=true;" type="radio" value="adbe7bd60fc4" /></td>
<td class="checkbox"><input id="cbto-4" name="rev_to" onclick="if ($('cb-4').checked==true) {$('cb-3').checked=true;}" type="radio" value="adbe7bd60fc4" /></td>
<td class="committed_on">21/08/2010 05:00 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Added tf2items_manager_playercontrol convar to prevent players using the control commands.</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/79154e18bf0f" title="Revision 171:79154e18bf0f">171:79154e18bf0f</a></td>
<td class="checkbox"><input id="cb-5" name="rev" onclick="$('cbto-6').checked=true;" type="radio" value="79154e18bf0f" /></td>
<td class="checkbox"><input id="cbto-5" name="rev_to" onclick="if ($('cb-5').checked==true) {$('cb-4').checked=true;}" type="radio" value="79154e18bf0f" /></td>
<td class="committed_on">21/08/2010 04:55 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Adding command for clients to disable getting weapons for that session. Bumping version to 1.4.1. Fixing preserve-attributes name.</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/efc73592a837" title="Revision 167:efc73592a837">167:efc73592a837</a></td>
<td class="checkbox"><input id="cb-6" name="rev" onclick="$('cbto-7').checked=true;" type="radio" value="efc73592a837" /></td>
<td class="checkbox"><input id="cbto-6" name="rev_to" onclick="if ($('cb-6').checked==true) {$('cb-5').checked=true;}" type="radio" value="efc73592a837" /></td>
<td class="committed_on">20/08/2010 05:45 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Merge</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/4fd7607c9a43" title="Revision 165:4fd7607c9a43">165:4fd7607c9a43</a></td>
<td class="checkbox"><input id="cb-7" name="rev" onclick="$('cbto-8').checked=true;" type="radio" value="4fd7607c9a43" /></td>
<td class="checkbox"><input id="cbto-7" name="rev_to" onclick="if ($('cb-7').checked==true) {$('cb-6').checked=true;}" type="radio" value="4fd7607c9a43" /></td>
<td class="committed_on">31/07/2010 05:02 am</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Updated version numbers; disabled debugging</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/0334a6f0b70e" title="Revision 158:0334a6f0b70e">158:0334a6f0b70e</a></td>
<td class="checkbox"><input id="cb-8" name="rev" onclick="$('cbto-9').checked=true;" type="radio" value="0334a6f0b70e" /></td>
<td class="checkbox"><input id="cbto-8" name="rev_to" onclick="if ($('cb-8').checked==true) {$('cb-7').checked=true;}" type="radio" value="0334a6f0b70e" /></td>
<td class="committed_on">22/07/2010 09:05 am</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Bumped version to 1.3.3</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/5319a3681f72" title="Revision 155:5319a3681f72">155:5319a3681f72</a></td>
<td class="checkbox"><input id="cb-9" name="rev" onclick="$('cbto-10').checked=true;" type="radio" value="5319a3681f72" /></td>
<td class="checkbox"><input id="cbto-9" name="rev_to" onclick="if ($('cb-9').checked==true) {$('cb-8').checked=true;}" type="radio" value="5319a3681f72" /></td>
<td class="committed_on">22/07/2010 08:38 am</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Added option to keep existing attibutes to tf2items_manager</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/d463c2bf3146" title="Revision 147:d463c2bf3146">147:d463c2bf3146</a></td>
<td class="checkbox"><input id="cb-10" name="rev" onclick="$('cbto-11').checked=true;" type="radio" value="d463c2bf3146" /></td>
<td class="checkbox"><input id="cbto-10" name="rev_to" onclick="if ($('cb-10').checked==true) {$('cb-9').checked=true;}" type="radio" value="d463c2bf3146" /></td>
<td class="committed_on">27/05/2010 04:27 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Changing version numbers to 1.3.2.1</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/35166aa4239d" title="Revision 141:35166aa4239d">141:35166aa4239d</a></td>
<td class="checkbox"><input id="cb-11" name="rev" onclick="$('cbto-12').checked=true;" type="radio" value="35166aa4239d" /></td>
<td class="checkbox"><input id="cbto-11" name="rev_to" onclick="if ($('cb-11').checked==true) {$('cb-10').checked=true;}" type="radio" value="35166aa4239d" /></td>
<td class="committed_on">25/05/2010 07:43 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Changed version number to 3.1.2</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/8ca6cc4b7562" title="Revision 97:8ca6cc4b7562">97:8ca6cc4b7562</a></td>
<td class="checkbox"><input id="cb-12" name="rev" onclick="$('cbto-13').checked=true;" type="radio" value="8ca6cc4b7562" /></td>
<td class="checkbox"><input id="cbto-12" name="rev_to" onclick="if ($('cb-12').checked==true) {$('cb-11').checked=true;}" type="radio" value="8ca6cc4b7562" /></td>
<td class="committed_on">21/03/2010 09:23 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Fixed all SourcePawn plugin's version numbers<br />Added new natives to include file</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/836cd322eea3" title="Revision 68:836cd322eea3">68:836cd322eea3</a></td>
<td class="checkbox"><input id="cb-13" name="rev" onclick="$('cbto-14').checked=true;" type="radio" value="836cd322eea3" /></td>
<td class="checkbox"><input id="cbto-13" name="rev_to" onclick="if ($('cb-13').checked==true) {$('cb-12').checked=true;}" type="radio" value="836cd322eea3" /></td>
<td class="committed_on">21/02/2010 05:02 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Added FCVAR_REPLICATED|FCVAR_NOTIFY to tf2items_manager convar.</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/d1e59cdb9ea3" title="Revision 59:d1e59cdb9ea3">59:d1e59cdb9ea3</a></td>
<td class="checkbox"><input id="cb-14" name="rev" onclick="$('cbto-15').checked=true;" type="radio" value="d1e59cdb9ea3" /></td>
<td class="checkbox"><input id="cbto-14" name="rev_to" onclick="if ($('cb-14').checked==true) {$('cb-13').checked=true;}" type="radio" value="d1e59cdb9ea3" /></td>
<td class="committed_on">17/02/2010 04:49 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Updated more files for 1.3.0</p></td>
</tr>


<tr class="changeset odd">
<td class="id"><a href="/projects/tf2items/repository/revisions/cce5505655d6" title="Revision 54:cce5505655d6">54:cce5505655d6</a></td>
<td class="checkbox"><input id="cb-15" name="rev" onclick="$('cbto-16').checked=true;" type="radio" value="cce5505655d6" /></td>
<td class="checkbox"><input id="cbto-15" name="rev_to" onclick="if ($('cb-15').checked==true) {$('cb-14').checked=true;}" type="radio" value="cce5505655d6" /></td>
<td class="committed_on">05/02/2010 07:40 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Committing the files for 1.3.0</p></td>
</tr>


<tr class="changeset even">
<td class="id"><a href="/projects/tf2items/repository/revisions/445bf519dc9a" title="Revision 52:445bf519dc9a">52:445bf519dc9a</a></td>
<td class="checkbox"></td>
<td class="checkbox"><input id="cbto-16" name="rev_to" onclick="if ($('cb-16').checked==true) {$('cb-15').checked=true;}" type="radio" value="445bf519dc9a" /></td>
<td class="committed_on">04/02/2010 11:06 pm</td>
<td class="author">Asherkin</td>
<td class="comments"><p>Updated tf2items_manager.sp to latest.</p></td>
</tr>


</tbody>
</table>
<input type="submit" value="View differences" />
</form>



        
				<div style="clear:both;"></div>
    </div>
</div>

<div id="ajax-indicator" style="display:none;"><span>Loading...</span></div>
	
<div id="footer">
  <div class="bgl"><div class="bgr">
    Powered by <a href="http://www.redmine.org/">Redmine</a> &copy; 2006-2011 Jean-Philippe Lang
  </div></div>
</div>
</div>
</div>

</body>
</html>
