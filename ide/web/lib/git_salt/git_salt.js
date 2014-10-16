// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/**
 *@constructor
 */
var GitSalt = function() {
};

/**
 * Create the Native Client <embed> element as a child of the DOM element
 * named "listener".
 *
 * @param {string} name The name of the example.
 * @param {string} path Directory name where .nmf file can be found.
 */
GitSalt.prototype.createNaClModule = function(name, path) {
  var moduleEl = document.createElement('embed');
  moduleEl.setAttribute('name', 'nacl_module');
  moduleEl.setAttribute('id', 'nacl_module');
  moduleEl.setAttribute('width', 0);
  moduleEl.setAttribute('height', 0);
  moduleEl.setAttribute('path', path);
  moduleEl.setAttribute('src', path + '/' + name + '.nmf');

  moduleEl.setAttribute('type', "application/x-nacl");

  // The <EMBED> element is wrapped inside a <DIV>, which has both a 'load'
  // and a 'message' event listener attached.  This wrapping method is used
  // instead of attaching the event listeners directly to the <EMBED> element
  // to ensure that the listeners are active before the NaCl module 'load'
  // event fires.
  var listenerDiv = document.getElementById('git-salt-container');
  listenerDiv.appendChild(moduleEl);
};

GitSalt.prototype.statusText = 'NO-STATUSES';

GitSalt.prototype.updateStatus = function(opt_message) {
  if (opt_message) {
    statusText = opt_message;
  }
  console.log(statusText);
}

/**
 * Add the default "load" and "message" event listeners to the element with
 * id "listener".
 *
 * The "load" event is sent when the module is successfully loaded. The
 * "message" event is sent when the naclModule posts a message using
 * PPB_Messaging.PostMessage() (in C) or pp::Instance().PostMessage() (in
 * C++).
 */
GitSalt.prototype.attachDefaultListeners = function() {
  var listenerDiv = document.getElementById('git-salt-container');
  listenerDiv.addEventListener('load', this.moduleDidLoad.bind(this), true);
  listenerDiv.addEventListener('message', this.handleMessage.bind(this), true);
  listenerDiv.addEventListener('error', this.handleError.bind(this), true);
  listenerDiv.addEventListener('crash', this.handleCrash.bind(this), true);
};

/**
 * Called when the NaCl module fails to load.
 *
 * This event listener is registered in createNaClModule above.
 */
GitSalt.prototype.handleError = function(event) {
  // We can't use GitSalt.naclModule yet because the module has not been
  // loaded.
  var moduleEl = document.getElementById('nacl_module');
  this.updateStatus('ERROR [' + moduleEl.lastError + ']');
};

/**
 * Called when the Browser can not communicate with the Module
 *
 * This event listener is registered in attachDefaultListeners above.
 */
GitSalt.prototype.handleCrash = function(event) {
  if (GitSalt.naclModule.exitStatus == -1) {
    this.updateStatus('CRASHED');
  } else {
    this.updateStatus('EXITED [' + this.naclModule.exitStatus + ']');
  }
  if (typeof window.handleCrash !== 'undefined') {
    window.handleCrash(this.naclModule.lastError);
  }
};

/**
 * Called when the NaCl module is loaded.
 *
 * This event listener is registered in attachDefaultListeners above.
 */
GitSalt.prototype.moduleDidLoad = function() {
  this.naclModule = document.getElementById('nacl_module');
  this.updateStatus('RUNNING');
  if (typeof window.moduleDidLoad !== 'undefined') {
    window.moduleDidLoad();
  }
};

/**
 * Hide the NaCl module's embed element.
 *
 * We don't want to hide by default; if we do, it is harder to determine that
 * a plugin failed to load. Instead, call this function inside the example's
 * "moduleDidLoad" function.
 *
 */
GitSalt.prototype.hideModule = function() {
  // Setting GitSalt.naclModule.style.display = "None" doesn't work; the
  // module will no longer be able to receive postMessages.
  this.naclModule.style.height = '0';
};

/**
 * Remove the NaCl module from the page.
 */
GitSalt.prototype.removeModule = function() {
  this.naclModule.parentNode.removeChild(this.naclModule);
  this.naclModule = null;
};

/**
 * Return true when |s| starts with the string |prefix|.
 *
 * @param {string} s The string to search.
 * @param {string} prefix The prefix to search for in |s|.
 */
GitSalt.prototype.startsWith = function(s, prefix) {
  // indexOf would search the entire string, lastIndexOf(p, 0) only checks at
  // the first index. See: http://stackoverflow.com/a/4579228
  return s.lastIndexOf(prefix, 0) === 0;
};

GitSalt.prototype.logMessage = function(message) {
  console.log(message);
};

GitSalt.prototype.defaultMessageTypes = {
  'alert': alert,
  'log': this.logMessage
};

/**
 * Called when the NaCl module sends a message to JavaScript (via
 * PPB_Messaging.PostMessage())
 *
 * This event listener is registered in createNaClModule above.
 *
 * @param {Event} message_event A message event. message_event.data contains
 *     the data sent from the NaCl module.
 */
GitSalt.prototype.handleMessage = function(message_event) {
  if (typeof message_event.data === 'string') {
    for (var type in this.defaultMessageTypes) {
      if (this.defaultMessageTypes.hasOwnProperty(type)) {
        if (this.startsWith(message_event.data, type + ':')) {
          func = this.defaultMessageTypes[type];
          func(message_event.data.slice(type.length + 1));
          return;
        }
      }
    }
  }

  if (typeof window.handleMessage !== 'undefined') {
    window.handleMessage(message_event);
    return;
  }

  this.logMessage('Unhandled message: ' + message_event.data);
};

/**
 * @param {string} name The name of the example.
 * @param {string} path Directory name where .nmf file can be found.
 */
GitSalt.prototype.loadPlugin = function(name, path) {
  this.attachDefaultListeners();
  this.createNaClModule(name, path);
};

GitSalt.prototype.postMessage = function(args) {
  this.naclModule.postMessage(args);
};

var gitSalt = new GitSalt();

// TODO(grv): implement callbacks to git-salt module.
function handleMessage(message_event) {
  console.log(message_event);
}